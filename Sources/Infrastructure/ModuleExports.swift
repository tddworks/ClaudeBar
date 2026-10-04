// Infrastructure is being emptied into context modules
// (docs/architecture/MODULAR_DESIGN.md §9). Until it is gone it re-exports
// them, so every file that imports Infrastructure keeps compiling unchanged.
@_exported import DataSources
@_exported import Diagnostics
