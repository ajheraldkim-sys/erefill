/// Finds database functions and tables the Dart code uses but the schema
/// lacks. Pure string scanning so it runs without Flutter or a database;
/// see schema_drift_check.dart for the command-line entry point.
library;

import 'dart:collection';

const _ident = r'[A-Za-z_][A-Za-z0-9_]*';

final _rpcCall = RegExp('''\\.rpc\\(\\s*['"]($_ident)['"]''');
final _fromCall = RegExp(
  '''\\.from\\(\\s*(?:['"]($_ident)['"]|DbTables\\.($_ident))''',
);
final _tableWatch = RegExp('''TableWatch\\(\\s*['"]($_ident)['"]''');
final _dbTableConst = RegExp(
  '''static\\s+const\\s+(?:String\\s+)?($_ident)\\s*=\\s*['"]([^'"]+)['"]''',
);

// Anchored to the start of a line so comments and GRANT/DROP lines that
// mention a function don't count as definitions.
final _sqlFunction = RegExp(
  r'^\s*create\s+(?:or\s+replace\s+)?function\s+(?:"?public"?\.)?"?'
  '($_ident)'
  r'"?\s*\(',
  caseSensitive: false,
  multiLine: true,
);
final _sqlTable = RegExp(
  r'^\s*create\s+(?:or\s+replace\s+)?(?:materialized\s+)?(?:table|view)\s+'
  r'(?:if\s+not\s+exists\s+)?(?:"?public"?\.)?"?'
  '($_ident)',
  caseSensitive: false,
  multiLine: true,
);

Set<String> extractRpcNames(String dartSource) =>
    {for (final m in _rpcCall.allMatches(dartSource)) m.group(1)!};

/// Tables named in `.from(...)` and realtime `TableWatch(...)` calls.
/// `storage.from('bucket')` names a storage bucket, not a table.
Set<String> extractTableNames(
  String dartSource,
  Map<String, String> dbTableConstants,
) {
  final tables = <String>{};
  for (final m in _fromCall.allMatches(dartSource)) {
    if (dartSource.substring(0, m.start).trimRight().endsWith('storage')) {
      continue;
    }
    final name = m.group(1) ?? dbTableConstants[m.group(2)];
    if (name != null) tables.add(name);
  }
  for (final m in _tableWatch.allMatches(dartSource)) {
    tables.add(m.group(1)!);
  }
  return tables;
}

Map<String, String> parseDbTableConstants(String dbTablesSource) => {
      for (final m in _dbTableConst.allMatches(dbTablesSource))
        m.group(1)!: m.group(2)!,
    };

Set<String> sqlDefinedFunctions(String sql) =>
    {for (final m in _sqlFunction.allMatches(sql)) m.group(1)!};

Set<String> sqlDefinedTables(String sql) =>
    {for (final m in _sqlTable.allMatches(sql)) m.group(1)!};

/// Used names (mapped to the files using them) that [defined] lacks.
SplayTreeMap<String, Set<String>> missing(
  Map<String, Set<String>> usage,
  Set<String> defined,
) =>
    SplayTreeMap.of({
      for (final entry in usage.entries)
        if (!defined.contains(entry.key)) entry.key: entry.value,
    });

/// Public-schema object names exported from the live database with the
/// query in schema_drift_check.dart.
class SchemaSnapshot {
  const SchemaSnapshot({required this.functions, required this.tables});

  final Set<String> functions;
  final Set<String> tables;

  factory SchemaSnapshot.fromJson(Map<String, dynamic> json) => SchemaSnapshot(
        functions: {...(json['functions'] as List? ?? const []).cast<String>()},
        tables: {...(json['tables'] as List? ?? const []).cast<String>()},
      );
}
