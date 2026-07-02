//
//  MLModelCache.swift
//  LocoKit2
//
//  Created on 2025-02-27.
//

import Foundation
import CoreML

@ActivityTypesActor
public enum MLModelCache {
    private static var loadedModels: [String: ModelPredictor] = [:]
    
    nonisolated
    public static let modelsDir: URL = {
        return try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MLModels", isDirectory: true)
    }()

    @discardableResult
    public static func predictorFor(filename: String) throws -> ModelPredictor? {
        if let cached = loadedModels[filename] {
            return cached
        }

        let modelURL = getModelURLFor(filename: filename)

        // mapmyway: skip MLModel init for non-bundled CD* files that don't exist
        // yet — CoreML otherwise prints "model is not found at URL" before our
        // catch block ever sees the error. Bundled (B*) paths force-unwrap the
        // bundle URL so they're always present when this code runs.
        if !filename.hasPrefix("B"),
           !FileManager.default.fileExists(atPath: modelURL.path) {
            return nil
        }

        do {
            // mapmyway: background inference is opt-in (ActivityClassifier) —
            // keep CoreML off the GPU so iOS doesn't penalise background GPU
            // work with termination. CPU + ANE cover these classifiers fully.
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let newModel = try MLModel(contentsOf: modelURL, configuration: config)
            let predictor = ModelPredictor(newModel)
            loadedModels[filename] = predictor
            return predictor

        } catch let error as MLModelError {
            let isMissingModelFile = (error as NSError).localizedDescription.contains(".mlmodelc") &&
                (error.code == .io || error.code == .generic)

            // "file not found" errors are just noise
            if isMissingModelFile {
                return nil
            }
            
            throw error
        }
    }
    
    nonisolated
    public static func getModelURLFor(filename: String) -> URL {
        if filename.hasPrefix("B") {
            return Bundle.main.url(forResource: filename, withExtension: nil)!
        }
        return modelsDir.appendingPathComponent(filename)
    }
    
    public static func invalidateModelFor(filename: String) {
        loadedModels.removeValue(forKey: filename)
    }
    
    public static func reloadModelFor(filename: String) throws {
        invalidateModelFor(filename: filename)
        try predictorFor(filename: filename)
    }
}
