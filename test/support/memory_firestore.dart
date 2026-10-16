import 'package:cloud_firestore/cloud_firestore.dart';

/// Deliberately small deterministic fake for the Logbook service contract.
/// Stages writes atomically and rejects reads after writes like Firestore.
class MemoryFirestore implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final queries = <String>[];
  bool failCommit = false;
  bool commitThenDeny = false;
  bool retryOnce = false;
  void Function()? beforeRetry;
  int _id = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      MemoryCollection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    var tx = MemoryTransaction(this);
    var result = await transactionHandler(tx);
    if (retryOnce) {
      retryOnce = false;
      beforeRetry?.call();
      tx = MemoryTransaction(this);
      result = await transactionHandler(tx);
    }
    if (failCommit) throw StateError('Injected commit failure');
    documents.addAll(tx.pending);
    if (commitThenDeny) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class MemoryCollection implements CollectionReference<Map<String, dynamic>> {
  MemoryCollection(
    this.database,
    this.path, [
    this.predicates = const [],
    this.maximum,
    this.after,
    this.order,
    this.descending = false,
  ]);
  final MemoryFirestore database;
  @override
  final String path;
  final List<bool Function(Map<String, dynamic>)> predicates;
  final int? maximum;
  final String? after;
  final String? order;
  final bool descending;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      MemoryDocument(database, '$path/${id ?? 'auto-${database._id++}'}');
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      final key = invocation.positionalArguments.first as String;
      final args = invocation.namedArguments;
      return MemoryCollection(
        database,
        path,
        [
          ...predicates,
          (data) {
            if (args[#isEqualTo] != null) return data[key] == args[#isEqualTo];
            final value = data[key] as Timestamp;
            if (args[#isGreaterThanOrEqualTo] != null) {
              return value.compareTo(
                    args[#isGreaterThanOrEqualTo] as Timestamp,
                  ) >=
                  0;
            }
            return value.compareTo(args[#isLessThan] as Timestamp) < 0;
          },
        ],
        maximum,
        after,
        order,
        descending,
      );
    }
    if (invocation.memberName == #limit) {
      return MemoryCollection(
        database,
        path,
        predicates,
        invocation.positionalArguments.first as int,
        after,
        order,
        descending,
      );
    }
    if (invocation.memberName == #orderBy) {
      return MemoryCollection(
        database,
        path,
        predicates,
        maximum,
        after,
        invocation.positionalArguments.first as String,
        invocation.namedArguments[#descending] as bool? ?? false,
      );
    }
    if (invocation.memberName == #startAfterDocument) {
      return MemoryCollection(
        database,
        path,
        predicates,
        maximum,
        (invocation.positionalArguments.first as DocumentSnapshot)
            .reference
            .path,
        order,
        descending,
      );
    }
    if (invocation.memberName == #get) {
      database.queries.add(path);
      var rows = database.documents.entries
          .where(
            (e) =>
                e.key.startsWith('$path/') &&
                e.key.split('/').length == path.split('/').length + 1 &&
                predicates.every((p) => p(e.value)),
          )
          .toList();
      rows.sort((a, b) {
        final primary = order == null
            ? 0
            : (a.value[order] as Timestamp).compareTo(
                b.value[order] as Timestamp,
              );
        final result = primary == 0 ? a.key.compareTo(b.key) : primary;
        return descending ? -result : result;
      });
      if (after != null) {
        rows = rows.skipWhile((e) => e.key != after).skip(1).toList();
      }
      if (maximum != null) rows = rows.take(maximum!).toList();
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        MemoryQuerySnapshot([
          for (final row in rows)
            MemorySnapshot(MemoryDocument(database, row.key), row.value),
        ]),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

// ignore: subtype_of_sealed_class
class MemoryDocument implements DocumentReference<Map<String, dynamic>> {
  MemoryDocument(this.database, this.path);
  final MemoryFirestore database;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      MemoryCollection(database, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => MemorySnapshot(this, database.documents[path]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class MemorySnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  MemorySnapshot(this.reference, this.value);
  final Map<String, dynamic>? value;
  @override
  final MemoryDocument reference;
  @override
  bool get exists => value != null;
  @override
  String get id => reference.id;
  @override
  Map<String, dynamic> data() => Map.from(value ?? {});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  MemoryQuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryTransaction implements Transaction {
  MemoryTransaction(this.database);
  final MemoryFirestore database;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    if (pending.isNotEmpty) throw StateError('Read after write');
    return MemorySnapshot(
          MemoryDocument(database, reference.path),
          database.documents[reference.path],
        )
        as DocumentSnapshot<T>;
  }

  dynamic _resolve(dynamic value) {
    if (value is FieldValue) {
      return Timestamp.fromDate(DateTime(2026, 10, 16, 16));
    }
    if (value is Map) {
      return {for (final e in value.entries) e.key: _resolve(e.value)};
    }
    return value;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    pending[reference.path] = {
      ...?database.documents[reference.path],
      ...Map<String, dynamic>.from(_resolve(data) as Map),
    };
    return this;
  }

  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    pending[reference.path] = {
      ...?database.documents[reference.path],
      ...Map<String, dynamic>.from(_resolve(data) as Map),
    };
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
