import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/vault_repository.dart';
import '../../domain/models/vault.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';

final _day = DateFormat('d MMM y');

/// Private document vault. Opening it asks for the vault PIN or the phone's
/// fingerprint / face, and it locks again when the app goes to the background.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});
  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _external = false; // a picker or viewer is open: do not re-lock
  bool? _hasPin;
  bool _bio = false;
  bool _bioAvailable = false;
  final _tempFiles = <File>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final f in _tempFiles) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_external && _unlocked) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _load() async {
    final user = ref.read(sessionProvider)!;
    final repo = ref.read(vaultRepositoryProvider);
    final has = await repo.hasPin(user);
    final bio = await repo.biometricEnabled(user);
    final avail = await ref.read(appLockProvider).isAvailable();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _bio = bio && avail;
      _bioAvailable = avail;
    });
    if (has && _bio) _biometric();
  }

  Future<void> _biometric() async {
    _external = true;
    final ok = await ref.read(appLockProvider).authenticate('Open your Document Vault');
    _external = false;
    if (ok && mounted) setState(() => _unlocked = true);
  }

  Future<T> _outside<T>(Future<T> Function() action) async {
    _external = true;
    try {
      return await action();
    } finally {
      _external = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_hasPin == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_hasPin!) {
      body = _SetPin(
        bioAvailable: _bioAvailable,
        onDone: (bio) {
          setState(() {
            _hasPin = true;
            _bio = bio;
            _unlocked = true;
          });
        },
      );
    } else if (!_unlocked) {
      body = _Unlock(
        bio: _bio,
        onBiometric: _biometric,
        onUnlocked: () => setState(() => _unlocked = true),
      );
    } else {
      body = _VaultHome(
        outside: _outside,
        tempFiles: _tempFiles,
        bioAvailable: _bioAvailable,
        bio: _bio,
        onBioChanged: (v) => setState(() => _bio = v),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Document Vault')),
      body: body,
    );
  }
}

// ------------------------------------------------------------------ PIN setup

class _SetPin extends ConsumerStatefulWidget {
  const _SetPin({required this.onDone, required this.bioAvailable});
  final void Function(bool biometric) onDone;
  final bool bioAvailable;
  @override
  ConsumerState<_SetPin> createState() => _SetPinState();
}

class _SetPinState extends ConsumerState<_SetPin> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _bio = true;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = VaultRepository.validatePin(_pin.text);
    if (err != null) return showMessage(context, err, error: true);
    if (_pin.text != _confirm.text) return showMessage(context, 'The PINs do not match.', error: true);
    setState(() => _busy = true);
    try {
      final user = ref.read(sessionProvider)!;
      final repo = ref.read(vaultRepositoryProvider);
      await repo.setPin(user, _pin.text);
      final useBio = _bio && widget.bioAvailable;
      await repo.setBiometric(user, useBio);
      widget.onDone(useBio);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.shield_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('Protect your vault', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Documents are encrypted on this phone and can only be opened by you. Choose a PIN '
          '(4 to 8 digits) to open the vault.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'New PIN', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'Confirm PIN', counterText: ''),
        ),
        if (widget.bioAvailable)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also unlock with fingerprint / face'),
            value: _bio,
            onChanged: (v) => setState(() => _bio = v),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create vault'),
        ),
      ]);
}

// --------------------------------------------------------------------- unlock

class _Unlock extends ConsumerStatefulWidget {
  const _Unlock({required this.bio, required this.onBiometric, required this.onUnlocked});
  final bool bio;
  final VoidCallback onBiometric, onUnlocked;
  @override
  ConsumerState<_Unlock> createState() => _UnlockState();
}

class _UnlockState extends ConsumerState<_Unlock> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final ok = await ref.read(vaultRepositoryProvider).verifyPin(ref.read(sessionProvider)!, _pin.text);
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() => _error = 'Wrong PIN.');
        _pin.clear();
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _forgot() async {
    final pw = TextEditingController();
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset vault PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your account password and choose a new PIN. Your documents are kept.'),
          const SizedBox(height: 12),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Account password')),
          const SizedBox(height: 8),
          TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'New PIN (4 to 8 digits)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset PIN')),
        ],
      ),
    );
    final password = pw.text, newPin = pin.text;
    disposeLater([pw]);
    disposeLater([pin]);
    if (ok != true || !mounted) return;
    try {
      await ref.read(vaultRepositoryProvider).resetPin(ref.read(sessionProvider)!, password, newPin);
      if (mounted) {
        setState(() => _error = null);
        showMessage(context, 'PIN changed. Enter the new PIN to open the vault.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('Vault locked', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        TextField(
          controller: _pin,
          obscureText: true,
          autofocus: !widget.bio,
          keyboardType: TextInputType.number,
          maxLength: 8,
          onSubmitted: (_) => _check(),
          decoration: InputDecoration(labelText: 'Vault PIN', errorText: _error, counterText: ''),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _check, child: const Text('Unlock')),
        if (widget.bio)
          TextButton.icon(
              onPressed: widget.onBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use fingerprint / face')),
        TextButton(onPressed: _forgot, child: const Text('Forgot PIN?')),
      ]);
}

// ----------------------------------------------------------------- vault home

class _VaultHome extends ConsumerStatefulWidget {
  const _VaultHome(
      {required this.outside,
      required this.tempFiles,
      required this.bio,
      required this.bioAvailable,
      required this.onBioChanged});
  final Future<T> Function<T>(Future<T> Function()) outside;
  final List<File> tempFiles;
  final bool bio, bioAvailable;
  final ValueChanged<bool> onBioChanged;
  @override
  ConsumerState<_VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends ConsumerState<_VaultHome> {
  String _query = '';
  VaultCategory? _category;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vaultDocsProvider);
    final now = DateTime.now();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add document'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search documents'),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            if (widget.bioAvailable)
              IconButton(
                tooltip: widget.bio ? 'Turn off fingerprint unlock' : 'Turn on fingerprint unlock',
                icon: Icon(widget.bio ? Icons.fingerprint : Icons.fingerprint_outlined),
                onPressed: () async {
                  final v = !widget.bio;
                  await ref.read(vaultRepositoryProvider).setBiometric(ref.read(sessionProvider)!, v);
                  widget.onBioChanged(v);
                },
              ),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(label: const Text('All'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
            ),
            for (final c in VaultCategory.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(label: Text(c.label), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
              ),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(vaultDocsProvider)),
            data: (all) {
              final list = all.where((d) {
                if (_category != null && d.category != _category) return false;
                return _query.isEmpty || '${d.title} ${d.originalName} ${d.category.label}'.toLowerCase().contains(_query);
              }).toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.folder_open_outlined,
                  message: all.isEmpty
                      ? 'Your vault is empty. Add an ID, bill or certificate. It is encrypted on this phone and only you can open it.'
                      : 'No documents match.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: list.length,
                itemBuilder: (_, i) => _DocTile(
                  doc: list[i],
                  now: now,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _DocScreen(docId: list[i].id, outside: widget.outside, tempFiles: widget.tempFiles))),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddSheet(outside: widget.outside),
    );
    if (added == true) ref.read(refreshTickProvider.notifier).state++;
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc, required this.now, required this.onTap});
  final VaultDocument doc;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = doc.daysToExpiry(now);
    final scheme = Theme.of(context).colorScheme;
    Widget? badge;
    if (days != null) {
      final expired = days < 0;
      final soon = !expired && days <= 30;
      final color = expired ? AppTheme.alert : soon ? AppTheme.ember : scheme.onSurfaceVariant;
      badge = Text(
        expired ? 'Expired' : soon ? 'Expires in $days d' : 'Valid to ${_day.format(doc.expiresAt!)}',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
      );
    }
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(doc.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, color: scheme.primary),
        title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${doc.category.label} · ${doc.sizeText}'),
          ?badge,
        ]),
        isThreeLine: badge != null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// --------------------------------------------------------------------- upload

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.outside});
  final Future<T> Function<T>(Future<T> Function()) outside;
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  VaultCategory _category = VaultCategory.aadhaar;
  final _title = TextEditingController();
  String? _fileName;
  List<int>? _bytes;
  DateTime? _expires;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _take(String name, List<int> bytes) {
    setState(() {
      _fileName = name;
      _bytes = bytes;
      if (_title.text.trim().isEmpty) _title.text = _category.label;
    });
  }

  Future<void> _pickFile() async {
    final res = await widget.outside(() => FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'], withData: true));
    final f = res?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) {
      if (mounted) showMessage(context, 'Could not read that file.', error: true);
      return;
    }
    _take(f.name, bytes);
  }

  Future<void> _scan() async {
    final x = await widget.outside(() => ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400));
    if (x == null) return;
    _take('scan_${DateTime.now().millisecondsSinceEpoch}.jpg', await x.readAsBytes());
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
    );
    if (d != null) setState(() => _expires = d);
  }

  Future<void> _save() async {
    if (_bytes == null) return showMessage(context, 'Choose a file first.', error: true);
    setState(() => _busy = true);
    try {
      await ref.read(vaultRepositoryProvider).add(ref.read(sessionProvider)!,
          category: _category, title: _title.text, fileName: _fileName!, bytes: _bytes!, expiresAt: _expires);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Add document', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<VaultCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final c in VaultCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => setState(() {
                _category = v!;
                if (_bytes != null && _title.text.trim().isEmpty) _title.text = v.label;
              }),
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'Name', counterText: '')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_file), label: const Text('Choose file'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo'))),
            ]),
            if (_fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Selected: $_fileName (${(_bytes!.length / 1024).toStringAsFixed(0)} KB)', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(_expires == null ? 'No expiry date' : 'Expires ${_day.format(_expires!)}'),
              subtitle: Text(_category.usuallyExpires ? 'Recommended: you will get reminders before it expires.' : 'Optional'),
              trailing: _expires == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _expires = null)),
              onTap: _pickDate,
            ),
            const Text('PDF, JPG, PNG or WebP, up to 10 MB. Encrypted before it is saved.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Encrypt and save'),
            ),
          ]),
        ),
      );
}

// ------------------------------------------------------------ document screen

class _DocScreen extends ConsumerStatefulWidget {
  const _DocScreen({required this.docId, required this.outside, required this.tempFiles});
  final String docId;
  final Future<T> Function<T>(Future<T> Function()) outside;
  final List<File> tempFiles;
  @override
  ConsumerState<_DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends ConsumerState<_DocScreen> {
  late Future<VaultFile> _file = _load();

  Future<VaultFile> _load() =>
      ref.read(vaultRepositoryProvider).open(ref.read(sessionProvider)!, widget.docId);

  Future<void> _rename(VaultDocument d) async {
    final c = TextEditingController(text: d.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c, maxLength: 80, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Save')),
        ],
      ),
    );
    final name = c.text;
    disposeLater([c]);
    if (ok != true) return;
    await _run(() => ref.read(vaultRepositoryProvider).rename(ref.read(sessionProvider)!, d.id, name));
  }

  Future<void> _expiry(VaultDocument d) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: d.expiresAt ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
    );
    if (date == null) return;
    await _run(() => ref.read(vaultRepositoryProvider).setExpiry(ref.read(sessionProvider)!, d.id, date));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) setState(() => _file = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _export(VaultFile f) async {
    final d = f.document;
    final name = d.originalName;
    final path = await widget.outside(() => FilePicker.platform.saveFile(
        dialogTitle: 'Save a copy', fileName: name, bytes: Uint8List.fromList(f.bytes)));
    if (path != null && mounted) {
      showMessage(context, 'Saved a copy. The copy is not encrypted, so keep it somewhere private.');
    }
  }

  Future<void> _openPdf(VaultFile f) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'civinex_${f.document.id}.pdf'));
    await file.writeAsBytes(f.bytes, flush: true);
    widget.tempFiles.add(file);
    final res = await widget.outside(() => OpenFilex.open(file.path, type: 'application/pdf'));
    if (res.type != ResultType.done && mounted) {
      showMessage(context, 'No PDF viewer found. Install one or use Save a copy.', error: true);
    }
  }

  Future<void> _delete(VaultDocument d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${d.title}" will be permanently removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(vaultRepositoryProvider).delete(ref.read(sessionProvider)!, d.id);
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VaultFile>(
        future: _file,
        builder: (context, snap) {
          final f = snap.data;
          return Scaffold(
            appBar: AppBar(title: Text(f?.document.title ?? 'Document')),
            body: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : snap.hasError
                    ? ErrorState(error: snap.error!, onRetry: () => setState(() => _file = _load()))
                    : _body(f!),
          );
        },
      );

  Widget _body(VaultFile f) {
    final d = f.document;
    final days = d.daysToExpiry(DateTime.now());
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (d.isImage)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InteractiveViewer(child: Image.memory(Uint8List.fromList(f.bytes), fit: BoxFit.contain)),
        )
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 64),
              const SizedBox(height: 8),
              Text(d.originalName),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => _openPdf(f), icon: const Icon(Icons.open_in_new), label: const Text('Open PDF')),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      ListTile(leading: const Icon(Icons.category_outlined), title: Text(d.category.label), subtitle: Text('${d.sizeText} · added ${_day.format(d.createdAt)}')),
      ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(d.expiresAt == null ? 'No expiry date' : (days! < 0 ? 'Expired ${_day.format(d.expiresAt!)}' : 'Expires ${_day.format(d.expiresAt!)}')),
        trailing: TextButton(onPressed: () => _expiry(d), child: Text(d.expiresAt == null ? 'Set' : 'Change')),
      ),
      const Divider(),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _rename(d), icon: const Icon(Icons.edit_outlined), label: const Text('Rename')),
        OutlinedButton.icon(onPressed: () => _export(f), icon: const Icon(Icons.download_outlined), label: const Text('Save a copy')),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => _delete(d),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
        ),
      ]),
    ]);
  }
}
