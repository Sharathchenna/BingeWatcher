import Accelerate
import Foundation

struct LinUCBState {
    var aMatrix: [Float]
    var bVector: [Float]

    static func initial(dimension: Int) -> LinUCBState {
        var matrix = Array(repeating: Float.zero, count: dimension * dimension)
        for index in 0..<dimension {
            matrix[(index * dimension) + index] = 1
        }
        return LinUCBState(aMatrix: matrix, bVector: Array(repeating: 0, count: dimension))
    }
}

struct LinUCBBandit {
    let alpha: Float
    let dimension: Int

    init(alpha: Float = 0.3, dimension: Int = FeatureVectorBuilder.vectorLength) {
        self.alpha = alpha
        self.dimension = dimension
    }

    func score(candidate: [Float], state: LinUCBState) -> Float {
        guard let inverse = invert(matrix: state.aMatrix) else {
            return 0
        }

        let theta = matrixVectorMultiply(inverse, state.bVector)
        let exploit = dot(theta, candidate)
        let exploreVector = matrixVectorMultiply(inverse, candidate)
        let explore = sqrt(max(dot(candidate, exploreVector), 0))
        return exploit + alpha * explore
    }

    func updatedState(from state: LinUCBState, with candidate: [Float], reward: Float) -> LinUCBState {
        var nextMatrix = state.aMatrix
        var nextVector = state.bVector

        var outer = Array(repeating: Float.zero, count: dimension * dimension)
        cblas_sger(CblasRowMajor, Int32(dimension), Int32(dimension), 1, candidate, 1, candidate, 1, &outer, Int32(dimension))
        vDSP.add(nextMatrix, outer, result: &nextMatrix)

        var rewardScaled = Array(repeating: Float.zero, count: dimension)
        vDSP.multiply(reward, candidate, result: &rewardScaled)
        vDSP.add(nextVector, rewardScaled, result: &nextVector)

        return LinUCBState(aMatrix: nextMatrix, bVector: nextVector)
    }

    func encodeMatrix(_ matrix: [Float]) -> Data {
        var mutable = matrix
        return Data(bytes: &mutable, count: mutable.count * MemoryLayout<Float>.size)
    }

    func decodeMatrix(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else {
            return LinUCBState.initial(dimension: dimension).aMatrix
        }

        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }

        guard values.count == dimension * dimension else {
            return LinUCBState.initial(dimension: dimension).aMatrix
        }

        return values
    }

    func encodeVector(_ vector: [Float]) -> Data {
        var mutable = vector
        return Data(bytes: &mutable, count: mutable.count * MemoryLayout<Float>.size)
    }

    func decodeVector(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else {
            return Array(repeating: 0, count: dimension)
        }

        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }

        if values.count == dimension {
            return values
        }

        var padded = Array(repeating: Float.zero, count: dimension)
        for (index, value) in values.prefix(dimension).enumerated() {
            padded[index] = value
        }
        return padded
    }

    private func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        vDSP.dot(lhs, rhs)
    }

    private func matrixVectorMultiply(_ matrix: [Float], _ vector: [Float]) -> [Float] {
        var result = Array(repeating: Float.zero, count: dimension)
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(dimension), Int32(dimension), 1, matrix, Int32(dimension), vector, 1, 0, &result, 1)
        return result
    }

    private func invert(matrix: [Float]) -> [Float]? {
        guard matrix.count == dimension * dimension else {
            return nil
        }

        var columnMajor = rowMajorToColumnMajor(matrix)
        var rowCount = __CLPK_integer(dimension)
        var columnCount = __CLPK_integer(dimension)
        var leadingDimension = __CLPK_integer(dimension)
        var pivots = Array(repeating: __CLPK_integer(), count: dimension)
        var workspace = Array(repeating: Float.zero, count: dimension * dimension)
        var workspaceSize = __CLPK_integer(dimension * dimension)
        var error: __CLPK_integer = 0

        sgetrf_(&rowCount, &columnCount, &columnMajor, &leadingDimension, &pivots, &error)
        guard error == 0 else {
            return nil
        }

        var inverseDimension = __CLPK_integer(dimension)
        var inverseLeadingDimension = __CLPK_integer(dimension)
        sgetri_(&inverseDimension, &columnMajor, &inverseLeadingDimension, &pivots, &workspace, &workspaceSize, &error)
        guard error == 0 else {
            return nil
        }

        return columnMajorToRowMajor(columnMajor)
    }

    private func rowMajorToColumnMajor(_ matrix: [Float]) -> [Float] {
        var converted = Array(repeating: Float.zero, count: matrix.count)
        for row in 0..<dimension {
            for column in 0..<dimension {
                converted[(column * dimension) + row] = matrix[(row * dimension) + column]
            }
        }
        return converted
    }

    private func columnMajorToRowMajor(_ matrix: [Float]) -> [Float] {
        var converted = Array(repeating: Float.zero, count: matrix.count)
        for row in 0..<dimension {
            for column in 0..<dimension {
                converted[(row * dimension) + column] = matrix[(column * dimension) + row]
            }
        }
        return converted
    }
}
