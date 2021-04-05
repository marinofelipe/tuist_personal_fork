import Foundation
import TSCBasic
@testable import TuistCore

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath) throws -> (Graph, Project))?
    public func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        return try loadProjectStub?(path) ?? (Graph.test(), Project.test())
    }

    public var loadWorkspaceStub: ((AbsolutePath) throws -> (Graph, Workspace))?
    public func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace) {
        return try loadWorkspaceStub?(path) ?? (Graph.test(), Workspace.test())
    }

    public var loadConfigStub: ((AbsolutePath) throws -> (Config))?
    public func loadConfig(path: AbsolutePath) throws -> Config {
        try loadConfigStub?(path) ?? Config.test()
    }
}