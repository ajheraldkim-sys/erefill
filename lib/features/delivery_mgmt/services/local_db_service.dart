import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/delivery_model.dart';
import '../models/rider_model.dart';
import '../models/credit_model.dart';
import '../models/inventory_model.dart';

class LocalDbService {
  static const _dbName = 'dm_local.db';
  static const _dbVersion = 2;
  static Database? _db;

  static const String tableRiders = 'dm_riders';
  static const String tableDeliveries = 'dm_deliveries';
  static const String tableCredits = 'dm_credits';
  static const String tableInventory = 'dm_inventory';
  static const String tableDeletions = 'dm_pending_deletions';

  static final _uuid = Uuid();

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDb,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableRiders (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        linked_user_id TEXT,
        full_name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        commission_per_gallon REAL DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableDeliveries (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        rider_id TEXT,
        rider_name TEXT,
        delivery_date TEXT NOT NULL,
        gallons REAL NOT NULL,
        price_per_gallon REAL NOT NULL,
        expenses REAL DEFAULT 0,
        notes TEXT,
        empty_gallons_returned REAL DEFAULT 0,
        commission REAL DEFAULT 0,
        credit_amount REAL DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        local_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableCredits (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        rider_id TEXT,
        rider_name TEXT,
        delivery_id TEXT,
        credit_type TEXT NOT NULL,
        debtor_name TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0,
        is_paid INTEGER DEFAULT 0,
        payment_date TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0,
        local_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableInventory (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        transaction_date TEXT NOT NULL,
        transaction_type TEXT NOT NULL,
        gallons REAL NOT NULL,
        notes TEXT,
        delivery_id TEXT,
        created_at TEXT
      )
    ''');

    await _createDeletionTable(db);
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createDeletionTable(db);
    }
  }

  Future<void> _createDeletionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDeletions (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      )
    ''');
  }

  // ─── RIDERS ──────────────────────────────────────────────────────────────

  Future<List<DmRider>> getRiders(String ownerId) async {
    final database = await db;
    final rows = await database.query(
      tableRiders,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'full_name ASC',
    );
    return rows.map(_riderFromRow).toList();
  }

  Future<String> insertRider(DmRider rider) async {
    final database = await db;
    final id = rider.id.isEmpty ? _uuid.v4() : rider.id;
    await database.insert(tableRiders, {
      'id': id,
      'owner_id': rider.ownerId,
      'linked_user_id': rider.linkedUserId,
      'full_name': rider.fullName,
      'phone': rider.phone,
      'email': rider.email,
      'commission_per_gallon': rider.commissionPerGallon,
      'is_synced': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<void> updateRider(DmRider rider) async {
    final database = await db;
    await database.update(
      tableRiders,
      {
        'linked_user_id': rider.linkedUserId,
        'full_name': rider.fullName,
        'phone': rider.phone,
        'email': rider.email,
        'commission_per_gallon': rider.commissionPerGallon,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [rider.id],
    );
  }

  Future<void> deleteRider(String id, String ownerId) async {
    final database = await db;
    await database.transaction((txn) async {
      await _queueDeletion(txn, 'rider', id, ownerId);
      await txn.delete(tableRiders, where: 'id = ?', whereArgs: [id]);
    });
  }

  DmRider _riderFromRow(Map<String, dynamic> row) {
    return DmRider(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      linkedUserId: row['linked_user_id'] as String?,
      fullName: row['full_name'] as String,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      commissionPerGallon:
          (row['commission_per_gallon'] as num?)?.toDouble() ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // ─── DELIVERIES ──────────────────────────────────────────────────────────

  Future<List<DmDelivery>> getDeliveries({
    required String ownerId,
    String? riderId,
    DateTime? from,
    DateTime? to,
  }) async {
    final database = await db;
    var where = 'owner_id = ?';
    final args = <dynamic>[ownerId];

    if (riderId != null) {
      where += ' AND rider_id = ?';
      args.add(riderId);
    }
    if (from != null) {
      where += ' AND delivery_date >= ?';
      args.add(
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
      );
    }
    if (to != null) {
      where += ' AND delivery_date <= ?';
      args.add(
        '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
      );
    }

    final rows = await database.query(
      tableDeliveries,
      where: where,
      whereArgs: args,
      orderBy: 'delivery_date DESC, created_at DESC',
    );
    return rows.map(_deliveryFromRow).toList();
  }

  Future<double> getRiderGallonsToday(String riderId, String ownerId) async {
    final database = await db;
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final rows = await database.query(
      tableDeliveries,
      columns: ['gallons'],
      where: 'rider_id = ? AND owner_id = ? AND delivery_date = ?',
      whereArgs: [riderId, ownerId, dateStr],
    );
    return rows.fold<double>(
      0,
      (sum, r) => sum + ((r['gallons'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<String> insertDelivery(DmDelivery delivery) async {
    final database = await db;
    final id = delivery.id.isEmpty ? _uuid.v4() : delivery.id;
    final now = DateTime.now().toIso8601String();
    await database.insert(tableDeliveries, {
      'id': id,
      'owner_id': delivery.ownerId,
      'rider_id': delivery.riderId,
      'rider_name': delivery.riderName,
      'delivery_date':
          '${delivery.deliveryDate.year}-${delivery.deliveryDate.month.toString().padLeft(2, '0')}-${delivery.deliveryDate.day.toString().padLeft(2, '0')}',
      'gallons': delivery.gallons,
      'price_per_gallon': delivery.pricePerGallon,
      'expenses': delivery.expenses,
      'notes': delivery.notes,
      'empty_gallons_returned': delivery.emptyGallonsReturned,
      'commission': delivery.commission,
      'credit_amount': delivery.creditAmount,
      'is_synced': 0,
      'local_id': id,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<void> updateDelivery(DmDelivery delivery) async {
    final database = await db;
    await database.update(
      tableDeliveries,
      {
        'rider_id': delivery.riderId,
        'rider_name': delivery.riderName,
        'delivery_date':
            '${delivery.deliveryDate.year}-${delivery.deliveryDate.month.toString().padLeft(2, '0')}-${delivery.deliveryDate.day.toString().padLeft(2, '0')}',
        'gallons': delivery.gallons,
        'price_per_gallon': delivery.pricePerGallon,
        'expenses': delivery.expenses,
        'notes': delivery.notes,
        'empty_gallons_returned': delivery.emptyGallonsReturned,
        'commission': delivery.commission,
        'credit_amount': delivery.creditAmount,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [delivery.id],
    );
  }

  Future<void> deleteDelivery(String id, String ownerId) async {
    final database = await db;
    await database.transaction((txn) async {
      await _queueDeletion(txn, 'delivery', id, ownerId);
      await txn.delete(tableDeliveries, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> restoreDelivery(DmDelivery delivery) async {
    await insertDelivery(delivery);
    await cancelDeletion('delivery', delivery.id);
  }

  Future<List<DmDelivery>> getUnsyncedDeliveries(String ownerId) async {
    final database = await db;
    final rows = await database.query(
      tableDeliveries,
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
    );
    return rows.map(_deliveryFromRow).toList();
  }

  Future<void> markDeliverySynced(String id) async {
    final database = await db;
    await database.update(
      tableDeliveries,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertDeliveryFromCloud(DmDelivery delivery) async {
    final database = await db;
    await database.insert(tableDeliveries, {
      'id': delivery.id,
      'owner_id': delivery.ownerId,
      'rider_id': delivery.riderId,
      'rider_name': delivery.riderName,
      'delivery_date':
          '${delivery.deliveryDate.year}-${delivery.deliveryDate.month.toString().padLeft(2, '0')}-${delivery.deliveryDate.day.toString().padLeft(2, '0')}',
      'gallons': delivery.gallons,
      'price_per_gallon': delivery.pricePerGallon,
      'expenses': delivery.expenses,
      'notes': delivery.notes,
      'empty_gallons_returned': delivery.emptyGallonsReturned,
      'commission': delivery.commission,
      'credit_amount': delivery.creditAmount,
      'is_synced': 1,
      'local_id': delivery.localId ?? delivery.id,
      'created_at': delivery.createdAt.toIso8601String(),
      'updated_at': delivery.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  DmDelivery _deliveryFromRow(Map<String, dynamic> row) {
    return DmDelivery(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      riderId: row['rider_id'] as String?,
      riderName: row['rider_name'] as String?,
      deliveryDate: DateTime.parse(row['delivery_date'] as String),
      gallons: (row['gallons'] as num).toDouble(),
      pricePerGallon: (row['price_per_gallon'] as num).toDouble(),
      expenses: (row['expenses'] as num?)?.toDouble() ?? 0,
      notes: row['notes'] as String?,
      emptyGallonsReturned:
          (row['empty_gallons_returned'] as num?)?.toDouble() ?? 0,
      commission: (row['commission'] as num?)?.toDouble() ?? 0,
      creditAmount: (row['credit_amount'] as num?)?.toDouble() ?? 0,
      isSynced: (row['is_synced'] as int? ?? 0) == 1,
      localId: row['local_id'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // ─── CREDITS ─────────────────────────────────────────────────────────────

  Future<List<DmCredit>> getCredits({
    required String ownerId,
    String? riderId,
    CreditType? type,
    bool? isPaid,
  }) async {
    final database = await db;
    var where = 'owner_id = ?';
    final args = <dynamic>[ownerId];

    if (riderId != null) {
      where += ' AND rider_id = ?';
      args.add(riderId);
    }
    if (type != null) {
      where += ' AND credit_type = ?';
      args.add(type == CreditType.rider ? 'rider' : 'customer');
    }
    if (isPaid != null) {
      where += ' AND is_paid = ?';
      args.add(isPaid ? 1 : 0);
    }

    final rows = await database.query(
      tableCredits,
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(_creditFromRow).toList();
  }

  Future<String> insertCredit(DmCredit credit) async {
    final database = await db;
    final id = credit.id.isEmpty ? _uuid.v4() : credit.id;
    final now = DateTime.now().toIso8601String();
    await database.insert(tableCredits, {
      'id': id,
      'owner_id': credit.ownerId,
      'rider_id': credit.riderId,
      'rider_name': credit.riderName,
      'delivery_id': credit.deliveryId,
      'credit_type': credit.creditType == CreditType.rider
          ? 'rider'
          : 'customer',
      'debtor_name': credit.debtorName,
      'amount': credit.amount,
      'paid_amount': credit.paidAmount,
      'is_paid': credit.isPaid ? 1 : 0,
      'payment_date': credit.paymentDate?.toIso8601String().split('T').first,
      'notes': credit.notes,
      'is_synced': 0,
      'local_id': id,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<void> updateCredit(DmCredit credit) async {
    final database = await db;
    await database.update(
      tableCredits,
      {
        'paid_amount': credit.paidAmount,
        'is_paid': credit.isPaid ? 1 : 0,
        'payment_date': credit.paymentDate?.toIso8601String().split('T').first,
        'notes': credit.notes,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [credit.id],
    );
  }

  Future<void> deleteCredit(String id, String ownerId) async {
    final database = await db;
    await database.transaction((txn) async {
      await _queueDeletion(txn, 'credit', id, ownerId);
      await txn.delete(tableCredits, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<DmCredit>> getUnsyncedCredits(String ownerId) async {
    final database = await db;
    final rows = await database.query(
      tableCredits,
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
    );
    return rows.map(_creditFromRow).toList();
  }

  Future<void> markCreditSynced(String id) async {
    final database = await db;
    await database.update(
      tableCredits,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertCreditFromCloud(DmCredit credit) async {
    final database = await db;
    await database.insert(tableCredits, {
      'id': credit.id,
      'owner_id': credit.ownerId,
      'rider_id': credit.riderId,
      'rider_name': credit.riderName,
      'delivery_id': credit.deliveryId,
      'credit_type': credit.creditType == CreditType.rider
          ? 'rider'
          : 'customer',
      'debtor_name': credit.debtorName,
      'amount': credit.amount,
      'paid_amount': credit.paidAmount,
      'is_paid': credit.isPaid ? 1 : 0,
      'payment_date': credit.paymentDate?.toIso8601String().split('T').first,
      'notes': credit.notes,
      'is_synced': 1,
      'local_id': credit.localId ?? credit.id,
      'created_at': credit.createdAt.toIso8601String(),
      'updated_at': credit.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  DmCredit _creditFromRow(Map<String, dynamic> row) {
    return DmCredit(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      riderId: row['rider_id'] as String?,
      riderName: row['rider_name'] as String?,
      deliveryId: row['delivery_id'] as String?,
      creditType: (row['credit_type'] as String?) == 'rider'
          ? CreditType.rider
          : CreditType.customer,
      debtorName: row['debtor_name'] as String,
      amount: (row['amount'] as num).toDouble(),
      paidAmount: (row['paid_amount'] as num?)?.toDouble() ?? 0,
      isPaid: (row['is_paid'] as int? ?? 0) == 1,
      paymentDate: row['payment_date'] != null
          ? DateTime.parse(row['payment_date'] as String)
          : null,
      notes: row['notes'] as String?,
      isSynced: (row['is_synced'] as int? ?? 0) == 1,
      localId: row['local_id'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // ─── INVENTORY ───────────────────────────────────────────────────────────

  Future<List<DmInventoryTx>> getInventoryTxs(String ownerId) async {
    final database = await db;
    final rows = await database.query(
      tableInventory,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'transaction_date DESC, created_at DESC',
    );
    return rows.map(_inventoryFromRow).toList();
  }

  Future<double> getCurrentStock(String ownerId) async {
    final txs = await getInventoryTxs(ownerId);
    double stock = 0;
    for (final tx in txs) {
      if (tx.transactionType == InventoryTxType.load) {
        stock += tx.gallons;
      } else if (tx.transactionType == InventoryTxType.deduct) {
        stock -= tx.gallons;
      } else {
        stock += tx.gallons; // adjustment can be negative
      }
    }
    return stock;
  }

  Future<String> insertInventoryTx(DmInventoryTx tx) async {
    final database = await db;
    final id = tx.id.isEmpty ? _uuid.v4() : tx.id;
    await database.insert(tableInventory, {
      'id': id,
      'owner_id': tx.ownerId,
      'transaction_date':
          '${tx.transactionDate.year}-${tx.transactionDate.month.toString().padLeft(2, '0')}-${tx.transactionDate.day.toString().padLeft(2, '0')}',
      'transaction_type': tx.transactionType.name,
      'gallons': tx.gallons,
      'notes': tx.notes,
      'delivery_id': tx.deliveryId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<void> upsertInventoryFromCloud(DmInventoryTx tx) async {
    final database = await db;
    await database.insert(tableInventory, {
      'id': tx.id,
      'owner_id': tx.ownerId,
      'transaction_date':
          '${tx.transactionDate.year}-${tx.transactionDate.month.toString().padLeft(2, '0')}-${tx.transactionDate.day.toString().padLeft(2, '0')}',
      'transaction_type': tx.transactionType.name,
      'gallons': tx.gallons,
      'notes': tx.notes,
      'delivery_id': tx.deliveryId,
      'created_at': tx.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  DmInventoryTx _inventoryFromRow(Map<String, dynamic> row) {
    return DmInventoryTx(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      transactionDate: DateTime.parse(row['transaction_date'] as String),
      transactionType: DmInventoryTx.parseType(
        row['transaction_type'] as String?,
      ),
      gallons: (row['gallons'] as num).toDouble(),
      notes: row['notes'] as String?,
      deliveryId: row['delivery_id'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
    );
  }

  // ─── PENDING CLOUD DELETIONS ─────────────────────────────────────────────

  Future<void> _queueDeletion(
    Transaction txn,
    String entityType,
    String entityId,
    String ownerId,
  ) async {
    await txn.insert(tableDeletions, {
      'entity_type': entityType,
      'entity_id': entityId,
      'owner_id': ownerId,
      'deleted_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingDeletion>> getPendingDeletions(String ownerId) async {
    final database = await db;
    final rows = await database.query(
      tableDeletions,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'deleted_at ASC',
    );
    return rows
        .map(
          (row) => PendingDeletion(
            entityType: row['entity_type'] as String,
            entityId: row['entity_id'] as String,
            ownerId: row['owner_id'] as String,
          ),
        )
        .toList();
  }

  Future<void> cancelDeletion(String entityType, String entityId) async {
    final database = await db;
    await database.delete(
      tableDeletions,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }
}

class PendingDeletion {
  final String entityType;
  final String entityId;
  final String ownerId;

  const PendingDeletion({
    required this.entityType,
    required this.entityId,
    required this.ownerId,
  });
}
