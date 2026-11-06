// Lists database functions and tables the app and admin code use that the
// schema doesn't define. Run from the repo root:
//
//   dart run tool/schema_drift_check.dart
//       Compares against every SQL file in supabase/scripts plus the schema
//       dump in supabase/backups. Catches names defined nowhere.
//
//   dart run tool/schema_drift_check.dart --snapshot supabase/schema_snapshot.json
//       Compares against the live database. Catches scripts never applied.
//       Export the snapshot by running this in the SQL editor and saving the
//       single JSON value it returns:
//
//         SELECT json_build_object(
//           'functions', (SELECT json_agg(DISTINCT proname ORDER BY proname)
//                         FROM pg_proc
//                         WHERE pronamespace = 'public'::regnamespace),
//           'tables',    (SELECT json_agg(relname ORDER BY relname)
//                         FROM pg_class
//                         WHERE relnamespace = 'public'::regnamespace
//                           AND relkind IN ('r', 'v', 'm', 'p', 'f')));
//
// Exits with status 1 when anything is missing.

import 'dart:convert';
import 'dart:io';

import 'schema_drift.dart';

const _codeRoots = ['lib', 'admin/lib'];
const _sqlSources = ['supabase/scripts', 'supabase/backups/supabase_schema_backup.sql'];

void main(List<String> args) {
  final snapshotIndex = args.indexOf('--snapshot');
  final snapshotPath =
      snapshotIndex >= 0 && snapshotIndex + 1 < args.length ? args[snapshotIndex + 1] : null;

  final constants = parseDbTableConstants(
    File('lib/core/db_tables.dart').readAsStringSync(),
  );
  final rpcUsage = <String, Set<String>>{};
  final tableUsage = <String, Set<String>>{};
  for (final file in _files(_codeRoots, '.dart')) {
    final source = file.readAsStringSync();
    final path = file.path.replaceAll(r'\', '/');
    for (final name in extractRpcNames(source)) {
      rpcUsage.putIfAbsent(name, () => {}).add(path);
    }
    for (final name in extractTableNames(source, constants)) {
      tableUsage.putIfAbsent(name, () => {}).add(path);
    }
  }

  final Set<String> functions;
  final Set<String> tables;
  final String against;
  if (snapshotPath != null) {
    final snapshot = SchemaSnapshot.fromJson(
      jsonDecode(File(snapshotPath).readAsStringSync()) as Map<String, dynamic>,
    );
    functions = snapshot.functions;
    tables = snapshot.tables;
    against = 'live schema snapshot $snapshotPath';
  } else {
    final sql = _files(_sqlSources, '.sql').map((f) => f.readAsStringSync()).join('\n');
    functions = sqlDefinedFunctions(sql);
    tables = sqlDefinedTables(sql);
    against = 'SQL in ${_sqlSources.join(', ')}';
  }

  final missingFunctions = missing(rpcUsage, functions);
  final missingTables = missing(tableUsage, tables);

  stdout.writeln(
    'Checked ${rpcUsage.length} functions and ${tableUsage.length} tables '
    'used in ${_codeRoots.join(', ')} against $against.',
  );
  _report('Missing functions', missingFunctions);
  _report('Missing tables', missingTables);

  if (missingFunctions.isEmpty && missingTables.isEmpty) {
    stdout.writeln('No drift found.');
  } else {
    exitCode = 1;
  }
}

Iterable<File> _files(List<String> roots, String extension) sync* {
  for (final root in roots) {
    if (FileSystemEntity.isFileSync(root)) {
      yield File(root);
    } else if (FileSystemEntity.isDirectorySync(root)) {
      yield* Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(extension));
    }
  }
}

void _report(String title, Map<String, Set<String>> found) {
  if (found.isEmpty) return;
  stdout.writeln('\n$title (${found.length}):');
  for (final MapEntry(:key, :value) in found.entries) {
    final files = value.toList()..sort();
    stdout.writeln('  $key  <- ${files.join(', ')}');
  }
}
