import { createHash } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

export const categories = ['users', 'farm_modules', 'batches', 'logbooks', 'inventory',
  'inventory_items', 'inventory_transactions', 'production_results', 'schedules',
  'finance_transactions', 'finance_records', 'sales', 'circular_flows',
  'education_contents', 'notifications', 'recommendations', 'report_metadata'];
const modules = ['ayam_kampung', 'maggot_bsf', 'cacing_tanah', 'tanaman', 'lele'];
const editable = {
  users: ['name', 'role', 'isActive', 'email'],
  farm_modules: ['name', 'description', 'isActive'],
  batches: ['name', 'locationName', 'notes', 'commodity', 'expectedHarvestAt', 'moduleType', 'startedAt', 'initialQuantity', 'initialUnit', 'status'],
  logbooks: ['title', 'notes'],
  inventory: ['name', 'category', 'location', 'minStock', 'moduleType', 'unit', 'isSellable', 'productType'],
  inventory_items: ['name', 'category', 'location', 'min_stock'],
  inventory_transactions: ['notes'],
  production_results: ['moduleType', 'productName', 'qualityStatus', 'notes', 'quantity', 'unit', 'harvestDate'],
  schedules: ['title', 'notes', 'date', 'status', 'type'],
  finance_transactions: ['type', 'category', 'amount', 'date', 'description', 'notes', 'paymentMethod'],
  finance_records: ['type', 'category', 'amount', 'date', 'description', 'notes'],
  sales: ['notes', 'buyerName'],
  circular_flows: ['materialName', 'quantity', 'unit', 'flowDate', 'notes'],
  education_contents: ['title', 'summary', 'content', 'type', 'status', 'moduleType', 'externalVideoUrl', 'steps', 'toolsNeeded', 'safetyNotes', 'category'],
  notifications: ['title', 'body', 'type', 'userId', 'targetRole'],
  recommendations: ['title', 'description', 'type', 'priority', 'moduleType', 'isResolved'],
  report_metadata: ['title', 'description', 'name', 'type'],
};
const creatable = new Set(['users', 'farm_modules', 'production_results', 'education_contents', 'notifications', 'recommendations', 'report_metadata']);
const referenceKeys = {
  batchId: 'batches', batch_id: 'batches', sourceBatchId: 'batches', destinationBatchId: 'batches',
  logbookId: 'logbooks', logbook_id: 'logbooks', itemId: 'inventory', item_id: 'inventory',
  inventoryItemId: 'inventory', inventory_item_id: 'inventory', saleId: 'sales', sale_id: 'sales',
  inventoryTransactionId: 'inventory_transactions', financeTransactionId: 'finance_transactions',
  createdBy: 'users', created_by: 'users', userId: 'users', authorId: 'users',
};
const clean = value => value instanceof Timestamp ? { seconds: value.seconds, nanoseconds: value.nanoseconds }
  : Array.isArray(value) ? value.map(clean) : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(k => [k, clean(value[k])])) : value;
export const digest = value => createHash('sha256').update(JSON.stringify(clean(value))).digest('hex');
const adminRole = d => typeof d?.role === 'string' && d.role.trim().toLowerCase() === 'admin';
const active = d => d.isDeleted !== true && d.is_deleted !== true && !d.adminReversed;
// Last-Admin protection must count only profiles that can actually authorize work.
const activeAdmin = d => !!d && adminRole(d) && d.isActive !== false && d.is_active !== false && active(d);
const fail = message => { throw new Error(message); };
function validPath(path) {
  if (typeof path !== 'string' || !/^[a-z_]+\/[A-Za-z0-9_-]{1,128}$/.test(path) || !categories.includes(path.split('/')[0])) fail('Jalur dokumen tidak valid.');
}
function references(d, path) {
  const [collection, id] = path.split('/');
  return Object.entries(d).some(([key, value]) =>
    (referenceKeys[key] === collection && value === id) || value === path) ||
    (d.relatedCollection === collection && d.relatedId === id) ||
    (d.sourceCollection === collection && d.sourceId === id);
}
function patchValue(key, value) {
  if (['date', 'expectedHarvestAt', 'harvestDate', 'flowDate', 'startedAt'].includes(key)) {
    const date = new Date(value);
    if (!Number.isFinite(date.getTime()) || date.getUTCFullYear() < 2020 || date.getUTCFullYear() > 2100) fail('Tanggal tidak valid.');
    return Timestamp.fromDate(date);
  }
  if (['quantity', 'amount', 'minStock', 'min_stock', 'initialQuantity'].includes(key) &&
      (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1e12)) fail('Angka tidak valid.');
  if (['isActive', 'isResolved', 'isSellable'].includes(key) && typeof value !== 'boolean') fail('Status tidak valid.');
  if (['steps', 'toolsNeeded'].includes(key)) {
    if (!Array.isArray(value) || value.some(v => typeof v !== 'string' || !v.trim())) fail('Daftar langkah/alat tidak valid.');
  } else if (!['quantity', 'amount', 'minStock', 'min_stock', 'isActive', 'isResolved', 'isSellable', 'initialQuantity'].includes(key) && typeof value !== 'string') fail('Teks tidak valid.');
  if (typeof value === 'string' && value.length > 20000) fail('Teks terlalu panjang.');
  return value;
}
function validate(category, d) {
  if (d.moduleType && !modules.includes(d.moduleType)) fail('Modul tidak valid.');
  if (category === 'users' && !['admin', 'operator_lapangan', 'operator_keuangan'].includes(d.role)) fail('Role tidak dapat diberikan.');
  if (['finance_transactions', 'finance_records'].includes(category) && (!['income', 'expense'].includes(d.type) || !Number.isFinite(d.amount) || d.amount <= 0)) fail('Transaksi keuangan tidak valid.');
  if (category === 'production_results' && (!d.productName?.trim() || !d.unit?.trim() || !Number.isFinite(d.quantity) || d.quantity <= 0 || !d.harvestDate)) fail('Hasil produksi tidak valid.');
  if (category === 'batches' && (!modules.includes(d.moduleType) || !['planned', 'active', 'completed', 'archived'].includes(d.status) ||
      (d.expectedHarvestAt && d.startedAt && d.expectedHarvestAt.toMillis() < d.startedAt.toMillis()))) fail('Batch atau tanggal tidak valid.');
  if (category === 'schedules' && !['pending', 'done', 'skipped'].includes(d.status)) fail('Status jadwal tidak valid.');
  if (category === 'education_contents') {
    if (!d.title?.trim() || !['draft', 'published', 'archived'].includes(d.status) || !['artikel', 'video', 'sop'].includes(d.type)) fail('Konten tidak valid.');
    if (d.type === 'artikel' && !d.content?.trim()) fail('Artikel wajib memiliki isi.');
    if (d.type === 'sop' && !d.steps?.length) fail('Langkah SOP wajib diisi.');
    if (d.type === 'video') {
      let url; try { url = new URL(d.externalVideoUrl); } catch { fail('URL video tidak valid.'); }
      if (url.protocol !== 'https:' || url.username || url.password) fail('Gunakan URL HTTPS tanpa kredensial.');
    }
  }
  if (category === 'notifications' && (!d.title?.trim() || !d.body?.trim() || (!d.userId && !['all', 'admin', 'operator_lapangan', 'operator_keuangan'].includes(d.targetRole)))) fail('Tujuan notifikasi tidak valid.');
  if (category === 'recommendations' && (!d.title?.trim() || !d.description?.trim() || !['high', 'medium', 'low'].includes(d.priority))) fail('Rekomendasi tidak valid.');
  if (category === 'farm_modules' && !d.name?.trim()) fail('Nama modul wajib diisi.');
}

/** Pure, deterministic mutation plan. All reads are supplied by a server transaction. */
export function planChange(records, request) {
  const { targetPath, operation, patch = {}, reason } = request;
  validPath(targetPath);
  if (typeof reason !== 'string' || reason.trim().length < 5 || reason.length > 1000) fail('Alasan minimal 5 karakter.');
  if (!['create', 'update', 'archive', 'softDelete', 'delete', 'reverse', 'deleteIdentity', 'restore'].includes(operation)) fail('Operasi tidak didukung.');
  const [category, id] = targetPath.split('/');
  const old = records[targetPath];
  if (old && ['delete', 'softDelete', 'reverse'].includes(operation) && category === 'logbooks' && !old.adminReversed) {
    const effectFields = ['dedak_padi_kg', 'talas_pepaya_kg', 'maggot_segar_kg', 'produksi_telur_hari_ini',
      'sampah_organik_kg', 'sampah_organik_masuk_kg', 'panen_maggot_kg', 'hasil_panen_maggot_kg',
      'media_bekas_maggot_kg', 'pakan_organik_kg', 'panen_kascing_kg', 'kascing_cair_liter',
      'pupuk_kascing_kg', 'hasil_panen_kg', 'pakan_maggot_pagi_kg', 'pakan_lele_kg', 'panen_lele_kg'];
    if (effectFields.some(k => Number(old.details?.[k]) > 0) &&
        !Object.entries(records).some(([p,d]) => p.startsWith('inventory_transactions/') && references(d,targetPath)))
      fail('Efek stok Logbook tidak lengkap; perlu bukti sumber sebelum penghapusan.');
  }
  if (operation === 'create' ? old : !old) fail(operation === 'create' ? 'ID sudah digunakan.' : 'Dokumen tidak ditemukan.');
  const incoming = Object.entries(records).filter(([path, d]) => path !== targetPath && references(d, targetPath));
  const writes = {};
  const deletions = [];
  const related = incoming.map(([path]) => path).sort();
  if (operation === 'create' || operation === 'update') {
    if (operation === 'create' && !creatable.has(category)) fail('Gunakan form operasional modul untuk membuat catatan ini.');
    if (!Object.keys(patch).length || Object.keys(patch).some(k => !editable[category].includes(k))) fail('Field tidak dapat diubah langsung. Balikkan sumber lalu catat ulang melalui form operasional.');
    if ((category === 'batches' && ['moduleType', 'startedAt', 'initialQuantity', 'initialUnit'].some(k => k in patch) ||
         category === 'inventory' && ['moduleType', 'unit'].some(k => k in patch)) && incoming.some(([, d]) => active(d))) fail('Selesaikan referensi sebelum migrasi field dasar.');
    const updates = Object.fromEntries(Object.entries(patch).map(([k, v]) => [k, patchValue(k, v)]));
    if (category === 'finance_transactions' && (old?.source === 'sale' || old?.saleId)) fail('Batalkan penjualan terkait sebelum koreksi keuangan.');
    if (category === 'production_results' && (old?.logbookId || incoming.some(([, d]) => active(d)))) fail('Koreksi melalui pembalikan Logbook sumber.');
    if (category === 'circular_flows' && (old?.inventoryTransactionId || old?.logbookId) && ['quantity', 'unit'].some(k => k in patch)) fail('Selesaikan referensi sumber sebelum mengubah jumlah/unit.');
    const next = { ...(old || {}), ...updates };
    if (category === 'users' && old?.identityPending && next.isActive === true) fail('Identitas belum terverifikasi.');
    if (category === 'users' && operation === 'create') Object.assign(next, { uid: id, isActive: false, identityPending: true });
    if (category === 'inventory') {
      if (![next.currentStock, next.minStock].every(Number.isFinite) || next.minStock < 0) fail('Saldo/minimum tidak valid.');
      next.isLowStock = next.currentStock <= next.minStock;
    }
    if (category === 'farm_modules' && operation === 'create' && !modules.includes(id)) fail('ID modul harus canonical.');
    if (category === 'finance_transactions' && !Number.isInteger(next.amount)) fail('Nominal rupiah harus bulat.');
    if (category === 'finance_transactions') next.version = (old?.version || 0) + 1;
    if (category === 'schedules' && next.status === 'pending') {
      for (const field of ['completedBy', 'completedAt', 'skippedBy', 'skippedAt', 'skipReason']) delete next[field];
    }
    validate(category, next);
    if (operation === 'create') Object.assign(next, { id, isDeleted: false, createdBy: request.actorUid });
    writes[targetPath] = next;
  } else if (operation === 'restore') {
    if (old.adminReversed) fail('Catatan yang sudah dibalikkan harus dicatat ulang dari sumber.');
    if (['sales', 'inventory_transactions', 'production_results'].includes(category)) fail('Gunakan koreksi sumber operasional.');
    writes[targetPath] = { ...old, isDeleted: false, is_deleted: false };
  } else if (operation === 'reverse') {
    if (old.adminReversed) fail('Catatan telah dibalikkan.');
    if (!['sales', 'logbooks', 'inventory_transactions'].includes(category)) fail('Pembalikan hanya untuk Penjualan, Logbook atau ledger manual.');
    if (category === 'inventory_transactions' && !['manual', 'opening'].includes(old.source)) fail('Balikkan dokumen sumber ledger ini.');
    const ledgers = category === 'inventory_transactions' ? [[targetPath, old]] : incoming.filter(([p]) => p.startsWith('inventory_transactions/'));
    const production = incoming.filter(([p]) => p.startsWith('production_results/'));
    const finance = incoming.filter(([p]) => p.startsWith('finance_transactions/'));
    const allowed = new Set([...ledgers, ...production, ...finance].map(([p]) => p));
    for (const [effectPath] of [...ledgers, ...production, ...finance]) {
      if (Object.entries(records).some(([p, d]) => p !== targetPath && p !== effectPath && active(d) &&
          references(d, effectPath) && !p.startsWith('notifications/') && !p.startsWith('recommendations/')))
        fail('Selesaikan referensi aktif ke efek sumber sebelum pembalikan.');
    }
    if (incoming.some(([p, d]) => active(d) && !allowed.has(p) && !p.startsWith('notifications/') && !p.startsWith('recommendations/'))) fail('Selesaikan dependensi aktif terlebih dahulu.');
    if (category === 'sales' && (ledgers.length !== 1 || finance.length !== 1 || ledgers[0][0] !== `inventory_transactions/${old.inventoryTransactionId}` || finance[0][0] !== `finance_transactions/${old.financeTransactionId}` || finance[0][1].amount !== old.totalAmount || ledgers[0][1].quantity !== old.quantity)) fail('Referensi penjualan tidak lengkap atau tidak cocok.');
    for (const [path, ledger] of ledgers) {
      if (ledger.isReversed || ledger.adminReversed) fail('Ledger telah dibalikkan.');
      const itemPath = `inventory/${ledger.itemId}`;
      const item = writes[itemPath] || records[itemPath];
      if (!item || !active(item)) fail('Master stok tidak tersedia; saldo fisik tidak boleh ditebak.');
      if (![ledger.beforeStock, ledger.afterStock, ledger.quantity, item.currentStock].every(Number.isFinite) || ledger.unit !== item.unit) fail('Bukti saldo/unit tidak lengkap.');
      const delta = ledger.afterStock - ledger.beforeStock;
      if (!((['in', 'opening'].includes(ledger.type) && delta === ledger.quantity) || (ledger.type === 'out' && delta === -ledger.quantity) || (ledger.type === 'correction' && Math.abs(delta) === ledger.quantity))) fail('Efek ledger tidak cocok.');
      const stock = item.currentStock - delta;
      if (stock < 0 || stock > 1e12) fail('Pembalikan akan menghasilkan saldo tidak valid. Selesaikan pemakaian terkait.');
      const reversalPath = `inventory_transactions/admin_${request.requestId}_${Object.keys(writes).length}`;
      if (records[reversalPath]) fail('ID pembalikan sudah digunakan.');
      writes[itemPath] = { ...item, currentStock: stock, isLowStock: stock <= item.minStock, lastTransactionId: reversalPath.split('/')[1] };
      writes[reversalPath] = { id: reversalPath.split('/')[1], itemId: ledger.itemId, itemName: item.name,
        itemKey: item.itemKey || '', unit: item.unit, moduleType: item.moduleType || '',
        type: delta > 0 ? 'out' : 'in', quantity: Math.abs(delta), beforeStock: item.currentStock, afterStock: stock,
        source: 'admin_reversal', reversalOf: path, requestId: request.requestId, notes: reason,
        createdBy: request.actorUid, isReversed: false };
      writes[path] = { ...ledger, isReversed: true, adminReversed: true, reversedBy: request.actorUid };
    }
    for (const [path, d] of [...production, ...finance]) writes[path] = { ...d, isDeleted: true, adminReversed: true };
    writes[targetPath] = { ...(writes[targetPath] || old), adminReversed: true,
      ...(category === 'sales' ? { status: 'cancelled' } : category === 'logbooks' ? { isDeleted: true } : {}) };
  } else {
    if (operation === 'deleteIdentity' && category !== 'users') fail('Identitas hanya untuk profil pengguna.');
    if (['logbooks', 'sales', 'inventory_transactions'].includes(category) && !old.adminReversed &&
        (category !== 'logbooks' || incoming.some(([p]) => /^(inventory_transactions|production_results)\//.test(p)))) fail('Balikkan sumber dan efek terkait terlebih dahulu.');
    if (category === 'finance_transactions' && (old.source === 'sale' || old.saleId) && !old.adminReversed) fail('Batalkan penjualan terkait.');
    if (category === 'production_results' && old.logbookId && !old.adminReversed) fail('Balikkan Logbook sumber sebelum menghapus hasil produksi.');
    // Only a terminal, adjacent inverse pair can be removed without rewriting later balances.
    const pair = operation === 'delete' && category === 'inventory_transactions' && old.adminReversed
      ? incoming.filter(([, d]) => d.source === 'admin_reversal' && d.reversalOf === targetPath) : [];
    if (pair.length) {
      if (pair.length !== 1) fail('Pasangan pembalikan tidak unik.');
      const [inversePath, inverse] = pair[0];
      const itemPath = `inventory/${old.itemId}`, item = records[itemPath];
      if (!item || inverse.beforeStock !== old.afterStock || inverse.afterStock !== old.beforeStock ||
          item.currentStock !== inverse.afterStock || item.lastTransactionId !== inverse.id)
        fail('Ledger memiliki aktivitas lanjutan; perlu manifest koreksi saldo yang terverifikasi.');
      if (Object.entries(records).some(([p,d]) => p !== targetPath && active(d) && references(d, inversePath)))
        fail('Pasangan pembalikan masih dirujuk catatan aktif.');
      const remaining = Object.entries(records).filter(([p,d]) => p.startsWith('inventory_transactions/') &&
        p !== targetPath && p !== inversePath && d.itemId === old.itemId && !d.isReversed && !d.adminReversed &&
        d.afterStock === item.currentStock && d.transactionDate instanceof Timestamp)
        .sort((a,b) => b[1].transactionDate.toMillis() - a[1].transactionDate.toMillis());
      if (!remaining.length && item.currentStock !== 0) fail('Ledger saldo sebelumnya belum terverifikasi.');
      writes[itemPath] = { ...item, lastTransactionId: remaining[0]?.[1].id || '' };
      deletions.push(inversePath);
    }
    const blocking = incoming.filter(([p, d]) => !pair.some(([inversePath]) => inversePath === p) && category !== 'users' && active(d) && !d.isReversed && !p.startsWith('notifications/') && !p.startsWith('recommendations/') &&
      !(category === 'inventory' && p.startsWith('inventory_transactions/')));
    if (blocking.length && !(operation === 'archive' && ['batches', 'users'].includes(category))) fail(`Selesaikan dependensi aktif: ${blocking.map(([p]) => p).join(', ')}`);
    if (['inventory', 'inventory_items'].includes(category) && operation !== 'archive' && (old.currentStock ?? old.current_stock) !== 0) fail('Stok harus terverifikasi nol sebelum dihapus. Gunakan koreksi stok dengan alasan.');
    if (operation === 'delete' || operation === 'deleteIdentity') deletions.push(targetPath);
    else writes[targetPath] = { ...old, ...(operation === 'archive'
      ? category === 'users' || category === 'farm_modules' ? { isActive: false }
        : ['batches', 'education_contents'].includes(category) ? { status: 'archived' } : { isDeleted: true }
      : { isDeleted: true }) };
  }
  if (category === 'users') {
    const next = writes[targetPath];
    const removesAdmin = activeAdmin(old) && !activeAdmin(next);
    if (removesAdmin && !Object.entries(records).some(([p, d]) => p.startsWith('users/') && p !== targetPath && activeAdmin(d))) fail('Admin aktif terakhir harus dipertahankan.');
    if (['delete', 'deleteIdentity'].includes(operation) && old.isActive !== false) fail('Nonaktifkan profil terlebih dahulu.');
    if (operation === 'update' && 'email' in patch) fail('Perubahan email identitas harus melalui Firebase Auth terverifikasi, bukan metadata profil.');
    if (operation === 'create' && (typeof patch.email !== 'string' || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(patch.email))) fail('Email akun wajib valid.');
  }
  const affected = [...new Set([...Object.keys(writes), ...deletions])].sort();
  if (affected.length > 100) fail('Operasi terlalu besar; perlu manifest khusus.');
  return { writes, deletions, affected, related };
}

async function readState(db, tx) {
  const records = {};
  for (const category of categories) {
    const snapshot = await tx.get(db.collection(category).limit(501));
    if (snapshot.size > 500) fail('Pemeriksaan dependensi melebihi 500 dokumen per kategori. Perlu manifest khusus.');
    for (const doc of snapshot.docs) records[doc.ref.path] = doc.data();
  }
  return records;
}
function authorize(records, uid) {
  const profile = records[`users/${uid}`];
  if (!activeAdmin(profile)) fail('Hanya Admin aktif yang berwenang.');
}

/** Request documents are untrusted. Revalidate identity, state, plan and preview at execution. */
export async function processRequest(db, requestId) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId)) fail('ID request tidak valid.');
  const ref = db.doc(`admin_requests/${requestId}`);
  try {
    await db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.data().status !== 'pending') return;
      const r = snap.data();
      if (!['preview', 'execute'].includes(r.kind)) fail('Jenis request tidak valid.');
      const records = await readState(db, tx);
      authorize(records, r.actorUid);
      const command = { ...r, requestId };
      const identityJob = r.kind === 'execute' && (r.operation === 'deleteIdentity' || (r.operation === 'create' && r.targetPath.startsWith('users/')));
      let original;
      if (r.kind === 'execute') {
        if (!/^[A-Za-z0-9_-]{1,128}$/.test(r.previewId || '')) fail('Preview wajib tersedia.');
        original = await tx.get(db.doc(`admin_requests/${r.previewId}`));
        const preview = original.data();
        if (!preview || preview.status !== 'ready' || preview.kind !== 'preview' || preview.actorUid !== r.actorUid ||
            Date.now() - preview.completedAt.toMillis() > 10 * 60 * 1000) fail('Preview kedaluwarsa/tidak valid.');
        if (digest({ targetPath: r.targetPath, operation: r.operation, patch: r.patch, reason: r.reason }) !==
            digest({ targetPath: preview.targetPath, operation: preview.operation, patch: preview.patch, reason: preview.reason })) fail('Permintaan berbeda dari preview.');
        if (preview.stateHash !== digest(records)) fail('Data berubah. Muat preview terbaru.');
        // Use the preview ID for deterministic reversal paths across retries.
        command.requestId = r.previewId;
      }
      const plan = planChange(records, command);
      const timestamp = FieldValue.serverTimestamp();
      if (r.kind === 'preview') {
        tx.update(ref, { status: 'ready', stateHash: digest(records), affected: plan.affected, related: plan.related,
          changes: plan.affected.map(path => ({ path, before: digest(records[path] || null), after: digest(plan.writes[path] || null),
            ...(path.startsWith('inventory/') ? { beforeStock: records[path]?.currentStock ?? null, afterStock: plan.writes[path]?.currentStock ?? null } : {}) })),
          consequences: r.operation === 'reverse' ? 'Efek stok/produksi/keuangan terkait dibalikkan secara atomik.' : 'Hanya dokumen dalam daftar dampak yang diubah. Histori audit tetap disimpan.',
          completedAt: timestamp });
        return;
      }
      // Audit children remain immutable at their original paths, even after parent removal.
      // Store the exact before/after set in a separate, server-only recovery collection.
      for (const path of plan.affected) {
        tx.create(db.doc(`admin_backups/${requestId}/documents/${path.replace('/', '__')}`), {
          targetPath: path, before: records[path] || null, after: plan.writes[path] || null, backedUpAt: timestamp,
        });
      }
      for (const [path, data] of Object.entries(plan.writes)) {
        tx.set(db.doc(path), { ...data, updatedBy: r.actorUid, updatedAt: timestamp,
          ...(!records[path] ? { createdAt: timestamp } : {}),
          ...(data.source === 'admin_reversal' ? { transactionDate: timestamp } : {}) });
      }
      for (const path of plan.deletions) {
        tx.delete(db.doc(path));
        tx.set(db.doc(`admin_tombstones/${path.replace('/', '__')}`), { targetPath: path, requestId, deletedAt: timestamp });
      }
      if (identityJob) tx.create(db.doc(`admin_identity_jobs/${requestId}`), { actorUid: r.actorUid, uid: r.targetPath.split('/')[1],
        action: r.operation === 'create' ? 'create' : 'delete', email: r.patch?.email || '', name: r.patch?.name || '', status: 'pending', createdAt: timestamp });
      tx.create(db.doc(`admin_audit/${requestId}`), { actorUid: r.actorUid, targetPath: r.targetPath,
        operation: r.operation, reason: r.reason, requestId, affected: plan.affected,
        beforeHash: digest(records), result: 'succeeded', createdAt: timestamp });
      tx.update(original.ref, { status: 'consumed', executedByRequest: requestId });
      tx.update(ref, { status: identityJob ? 'identity_pending' : 'succeeded', affected: plan.affected, completedAt: timestamp });
    });
  } catch (error) {
    await db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (snap.data()?.status === 'pending') {
        tx.update(ref, { status: 'failed', error: String(error.message).slice(0, 1000), completedAt: FieldValue.serverTimestamp() });
        tx.create(db.doc(`admin_audit/${requestId}_failed`), { actorUid: snap.data().actorUid || '', targetPath: String(snap.data().targetPath || '').slice(0, 256),
          operation: snap.data().operation || '', requestId, result: 'failed', createdAt: FieldValue.serverTimestamp() });
      }
    });
  }
}
