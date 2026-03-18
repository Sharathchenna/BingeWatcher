from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path
from typing import Any, cast

import numpy as np
import pandas as pd
from scipy.sparse import coo_matrix
from scipy.sparse.linalg import svds


READ_DTYPES = {"userId": np.int32, "movieId": np.int32, "rating": np.float32}
LINK_USECOLS = ("movieId", "tmdbId")
MOVIEID_USECOLS = ("movieId",)
RATING_USECOLS = ("userId", "movieId", "rating")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build CineMatch collaborative lookup tables from MovieLens ratings data."
    )
    parser.add_argument(
        "--ratings", type=Path, required=True, help="Path to MovieLens ratings.csv"
    )
    parser.add_argument(
        "--links", type=Path, required=True, help="Path to MovieLens links.csv"
    )
    parser.add_argument("--output", type=Path, required=True, help="Output SQLite path")
    parser.add_argument("--rank", type=int, default=64, help="Truncated SVD rank")
    parser.add_argument("--neighbors", type=int, default=50, help="Neighbors per movie")
    parser.add_argument(
        "--min-ratings",
        type=int,
        default=25,
        help="Minimum ratings per movie to include",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=1_000_000,
        help="CSV chunk size for ratings ingest",
    )
    parser.add_argument(
        "--similarity-batch-size",
        type=int,
        default=2_000,
        help="Batch size for blockwise cosine similarity",
    )
    parser.add_argument(
        "--sqlite-batch-size",
        type=int,
        default=25_000,
        help="Batch size for SQLite inserts",
    )
    return parser.parse_args()


def validate_inputs(ratings_path: Path, links_path: Path, output_path: Path) -> None:
    if not ratings_path.exists():
        raise FileNotFoundError(f"ratings.csv not found: {ratings_path}")
    if not links_path.exists():
        raise FileNotFoundError(f"links.csv not found: {links_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)


def load_links(links_path: Path) -> pd.DataFrame:
    links = pd.read_csv(links_path, usecols=cast(Any, LINK_USECOLS))
    links = links.dropna(subset=["tmdbId"]).copy()
    links["movieId"] = links["movieId"].astype(np.int64)
    links["tmdbId"] = links["tmdbId"].astype(np.int64)
    links = links.drop_duplicates(subset=["movieId"])
    links = links.sort_values("movieId").drop_duplicates(
        subset=["tmdbId"], keep="first"
    )
    return links.reset_index(drop=True)


def collect_rating_counts(
    ratings_path: Path, valid_movie_ids: set[int], chunk_size: int
) -> pd.Series:
    counts: dict[int, int] = {}
    for chunk in pd.read_csv(
        ratings_path,
        usecols=cast(Any, MOVIEID_USECOLS),
        chunksize=chunk_size,
        dtype=cast(Any, {"movieId": np.int32}),
    ):
        filtered = chunk[chunk["movieId"].isin(valid_movie_ids)]
        if filtered.empty:
            continue
        grouped = filtered.groupby("movieId").size()
        for movie_id, count in grouped.items():
            counts[int(movie_id)] = counts.get(int(movie_id), 0) + int(count)
    return pd.Series(counts, dtype=np.int64)


def load_filtered_ratings(
    ratings_path: Path,
    valid_movie_ids: set[int],
    eligible_movie_ids: set[int],
    chunk_size: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    user_parts: list[np.ndarray] = []
    movie_parts: list[np.ndarray] = []
    rating_parts: list[np.ndarray] = []
    valid_ids = np.fromiter(valid_movie_ids, dtype=np.int32)
    eligible_ids = np.fromiter(eligible_movie_ids, dtype=np.int32)

    for chunk in pd.read_csv(
        ratings_path,
        usecols=cast(Any, RATING_USECOLS),
        chunksize=chunk_size,
        dtype=cast(Any, READ_DTYPES),
    ):
        filtered = chunk[
            chunk["movieId"].isin(valid_ids) & chunk["movieId"].isin(eligible_ids)
        ]
        if filtered.empty:
            continue
        user_parts.append(filtered["userId"].to_numpy(copy=True))
        movie_parts.append(filtered["movieId"].to_numpy(copy=True))
        rating_parts.append(filtered["rating"].to_numpy(copy=True))

    if not user_parts:
        raise ValueError(
            "No ratings matched the provided links and filtering thresholds."
        )

    user_ids = np.concatenate(user_parts).astype(np.int32, copy=False)
    movie_ids = np.concatenate(movie_parts).astype(np.int32, copy=False)
    ratings = np.concatenate(rating_parts).astype(np.float32, copy=False)
    return user_ids, movie_ids, ratings


def build_rating_matrix(
    user_ids: np.ndarray,
    movie_ids: np.ndarray,
    ratings: np.ndarray,
) -> tuple[coo_matrix, pd.DataFrame, pd.DataFrame]:
    unique_movie_ids, movie_idx = np.unique(movie_ids, return_inverse=True)
    unique_user_ids, user_idx = np.unique(user_ids, return_inverse=True)

    movie_index = pd.DataFrame(
        {
            "movieId": unique_movie_ids.astype(np.int64),
            "movie_idx": np.arange(unique_movie_ids.shape[0], dtype=np.int64),
        }
    )
    user_index = pd.DataFrame(
        {
            "userId": unique_user_ids.astype(np.int64),
            "user_idx": np.arange(unique_user_ids.shape[0], dtype=np.int64),
        }
    )

    rating_sums = np.bincount(
        movie_idx, weights=ratings, minlength=unique_movie_ids.shape[0]
    )
    rating_counts = np.bincount(movie_idx, minlength=unique_movie_ids.shape[0])
    movie_means = rating_sums / np.maximum(rating_counts, 1)
    centered = ratings - movie_means[movie_idx]

    matrix = coo_matrix(
        (
            centered.astype(np.float32, copy=False),
            (movie_idx, user_idx),
        ),
        shape=(len(movie_index), len(user_index)),
        dtype=np.float32,
    )
    return matrix, movie_index, user_index


def compute_latent_factors(matrix: coo_matrix, rank: int) -> np.ndarray:
    shape = cast(tuple[int, int], matrix.shape)
    max_rank = min(shape[0], shape[1]) - 1
    if max_rank < 1:
        raise ValueError("Rating matrix is too small to compute SVD.")

    actual_rank = min(rank, max_rank)
    u, s, _ = cast(
        tuple[np.ndarray, np.ndarray, np.ndarray], svds(matrix.tocsr(), k=actual_rank)
    )
    order = np.argsort(s)[::-1]
    u = u[:, order]
    s = s[order]
    factors = u @ np.diag(np.sqrt(s))
    return factors.astype(np.float32)


def top_k_neighbors(
    latent_factors: np.ndarray, k: int, batch_size: int
) -> dict[int, list[tuple[int, float]]]:
    normalized = latent_factors.copy()
    norms = np.linalg.norm(normalized, axis=1, keepdims=True)
    norms[norms == 0] = 1
    normalized /= norms

    neighbors: dict[int, list[tuple[int, float]]] = {}
    movie_count = normalized.shape[0]

    for start in range(0, movie_count, batch_size):
        stop = min(start + batch_size, movie_count)
        block = normalized[start:stop]
        similarity_block = block @ normalized.T

        row_indices = np.arange(start, stop)
        similarity_block[np.arange(stop - start), row_indices] = -1

        candidate_count = min(k, movie_count - 1)
        if candidate_count <= 0:
            for movie_idx in range(start, stop):
                neighbors[movie_idx] = []
            continue

        partition = np.argpartition(similarity_block, -candidate_count, axis=1)[
            :, -candidate_count:
        ]
        partition_scores = np.take_along_axis(similarity_block, partition, axis=1)
        order = np.argsort(partition_scores, axis=1)[:, ::-1]
        sorted_indices = np.take_along_axis(partition, order, axis=1)
        sorted_scores = np.take_along_axis(partition_scores, order, axis=1)

        for offset, movie_idx in enumerate(range(start, stop)):
            row_scores = sorted_scores[offset]
            row_neighbors = sorted_indices[offset]
            neighbors[movie_idx] = [
                (int(neighbor_idx), float(score))
                for neighbor_idx, score in zip(row_neighbors, row_scores, strict=False)
                if score > 0
            ]

    return neighbors


def write_database(
    output_path: Path,
    movie_index: pd.DataFrame,
    links: pd.DataFrame,
    latent_factors: np.ndarray,
    neighbors: dict[int, list[tuple[int, float]]],
    sqlite_batch_size: int,
) -> None:
    merged = movie_index.merge(links, on="movieId", how="inner")
    tmdb_by_idx = dict(zip(merged["movie_idx"], merged["tmdbId"]))

    if output_path.exists():
        output_path.unlink()

    connection = sqlite3.connect(output_path)
    cursor = connection.cursor()
    cursor.executescript(
        """
        CREATE TABLE movie_factors (
            tmdb_id INTEGER NOT NULL,
            factor_index INTEGER NOT NULL,
            factor_value REAL NOT NULL,
            PRIMARY KEY (tmdb_id, factor_index)
        );

        CREATE TABLE movie_neighbors (
            source_tmdb_id INTEGER NOT NULL,
            neighbor_tmdb_id INTEGER NOT NULL,
            neighbor_rank INTEGER NOT NULL,
            similarity REAL NOT NULL,
            PRIMARY KEY (source_tmdb_id, neighbor_rank)
        );

        CREATE INDEX idx_movie_neighbors_source ON movie_neighbors(source_tmdb_id);
        """
    )

    factor_rows: list[tuple[int, int, float]] = []
    for movie_idx, tmdb_id in tmdb_by_idx.items():
        for factor_index, value in enumerate(latent_factors[int(movie_idx)]):
            factor_rows.append((int(tmdb_id), factor_index, float(value)))
            if len(factor_rows) >= sqlite_batch_size:
                cursor.executemany(
                    "INSERT INTO movie_factors (tmdb_id, factor_index, factor_value) VALUES (?, ?, ?)",
                    factor_rows,
                )
                factor_rows.clear()
    if factor_rows:
        cursor.executemany(
            "INSERT INTO movie_factors (tmdb_id, factor_index, factor_value) VALUES (?, ?, ?)",
            factor_rows,
        )

    neighbor_rows: list[tuple[int, int, int, float]] = []
    for source_idx, similar_movies in neighbors.items():
        source_tmdb_id = tmdb_by_idx.get(source_idx)
        if source_tmdb_id is None:
            continue
        for rank, (neighbor_idx, score) in enumerate(similar_movies, start=1):
            neighbor_tmdb_id = tmdb_by_idx.get(neighbor_idx)
            if neighbor_tmdb_id is None:
                continue
            neighbor_rows.append(
                (int(source_tmdb_id), int(neighbor_tmdb_id), rank, float(score))
            )
            if len(neighbor_rows) >= sqlite_batch_size:
                cursor.executemany(
                    "INSERT INTO movie_neighbors (source_tmdb_id, neighbor_tmdb_id, neighbor_rank, similarity) VALUES (?, ?, ?, ?)",
                    neighbor_rows,
                )
                neighbor_rows.clear()
    if neighbor_rows:
        cursor.executemany(
            "INSERT INTO movie_neighbors (source_tmdb_id, neighbor_tmdb_id, neighbor_rank, similarity) VALUES (?, ?, ?, ?)",
            neighbor_rows,
        )

    connection.commit()
    connection.close()


def main() -> None:
    args = parse_args()
    validate_inputs(args.ratings, args.links, args.output)

    links = load_links(args.links)
    valid_movie_ids = set(links["movieId"].tolist())
    counts_by_movie = collect_rating_counts(
        args.ratings, valid_movie_ids, args.chunk_size
    )

    eligible_movie_ids = {
        int(movie_id)
        for movie_id, count in counts_by_movie.to_dict().items()
        if int(count) >= args.min_ratings
    }
    user_ids, movie_ids, ratings = load_filtered_ratings(
        args.ratings, valid_movie_ids, eligible_movie_ids, args.chunk_size
    )
    matrix, movie_index, _ = build_rating_matrix(user_ids, movie_ids, ratings)
    latent_factors = compute_latent_factors(matrix, args.rank)
    neighbors = top_k_neighbors(
        latent_factors, args.neighbors, args.similarity_batch_size
    )
    write_database(
        args.output,
        movie_index,
        links,
        latent_factors,
        neighbors,
        args.sqlite_batch_size,
    )


if __name__ == "__main__":
    main()
