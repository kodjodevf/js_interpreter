library;

import '../parser/ast_nodes.dart';
import 'environment.dart';
import 'js_value.dart';

enum ModuleStatus {
  unlinked,
  linking,
  linked,
  evaluating,
  evaluatingAsync,
  evaluated,
  error,
}

class JSModule {
  final String id;
  final Map<String, JSValue> exports = {};
  JSValue? defaultExport;
  bool isLoaded = false;
  late Environment environment;
  Program? ast;

  bool hasTopLevelAwait = false;
  ModuleStatus status = ModuleStatus.unlinked;
  JSPromise? evaluationPromise;
  JSValue? evaluationError;

  final List<String> requestedModules = [];
  final List<JSModule> loadedRequestedModules = [];

  int? dfsIndex;
  int? dfsAncestorIndex;
  bool? hasTLA;
  bool? cycleRoot;
  List<JSModule>? asyncParentModules;

  JSModule(this.id, Environment globalEnvironment) {
    environment = Environment.module(globalEnvironment);
  }

  bool get isReadyToExecute {
    if (status != ModuleStatus.linked) return false;
    return loadedRequestedModules.every(
      (m) =>
          m.status == ModuleStatus.evaluated ||
          m.status == ModuleStatus.evaluatingAsync,
    );
  }
}
