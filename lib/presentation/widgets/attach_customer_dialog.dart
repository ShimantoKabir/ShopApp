import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customer_rules.dart';
import '../../domain/sales.dart';
import '../../domain/services.dart';
import 'contact_pick_button.dart';

/// Asks for the customer of a sale that was made without one: one number (ask
/// for their WhatsApp number, the receipt and reminders go there) and, if
/// they want to give them, a name, address and NID. When the sale has a due
/// ([dueRequired]) the name, address and NID are required too.
///
/// [lookUp] (optional) finds a customer seen before by that number, to fill in
/// what we already know. With a [picker], the number field offers "choose from
/// contacts". Returns null if cancelled.
Future<CustomerInfo?> showAttachCustomerDialog(
  BuildContext context, {
  CustomerInfo initial = const CustomerInfo(),
  bool dueRequired = false,
  Future<CustomerInfo?> Function(String number)? lookUp,
  ContactPicker? picker,
}) =>
    showDialog<CustomerInfo>(
      context: context,
      builder: (_) => _AttachCustomerDialog(initial: initial, dueRequired: dueRequired, lookUp: lookUp, picker: picker),
    );

class _AttachCustomerDialog extends StatefulWidget {
  final CustomerInfo initial;
  final bool dueRequired;
  final Future<CustomerInfo?> Function(String number)? lookUp;
  final ContactPicker? picker;
  const _AttachCustomerDialog({required this.initial, required this.dueRequired, this.lookUp, this.picker});

  @override
  State<_AttachCustomerDialog> createState() => _AttachCustomerDialogState();
}

class _AttachCustomerDialogState extends State<_AttachCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _mobile = TextEditingController(
    text: widget.initial.whatsapp.isNotEmpty ? widget.initial.whatsapp : widget.initial.mobile,
  );
  late final _name = TextEditingController(text: widget.initial.name);
  late final _address = TextEditingController(text: widget.initial.address);
  late final _nid = TextEditingController(text: widget.initial.nid);
  final Set<String> _lookedUp = {};
  bool _known = false;

  @override
  void initState() {
    super.initState();
    _mobile.addListener(_numberChanged);
  }

  @override
  void dispose() {
    for (final c in [_mobile, _name, _address, _nid]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A customer seen before: fill in what we know (never over what was typed).
  Future<void> _numberChanged() async {
    final lookUp = widget.lookUp;
    final number = normalizeMobile(_mobile.text);
    if (lookUp == null || !isValidMobile(number) || !_lookedUp.add(number)) return;
    final known = await lookUp(number);
    if (!mounted || known == null) return;
    void fill(TextEditingController c, String value) {
      if (c.text.trim().isEmpty && value.isNotEmpty) c.text = value;
    }

    setState(() {
      _known = true;
      fill(_name, known.name);
      fill(_address, known.address);
      fill(_nid, known.nid);
    });
  }

  String _label(String base, {required bool required}) => required ? '$base *' : base;

  String? _required(String? v) => (widget.dueRequired && (v ?? '').trim().isEmpty) ? Bn.requiredForDue : null;

  String? _numberError(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return Bn.saleContactRequired;
    return isValidMobile(text) ? null : Bn.mobileInvalid;
  }

  String? _nidError(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return widget.dueRequired ? Bn.requiredForDue : null;
    return isValidNid(text) ? null : Bn.nidInvalid;
  }

  /// Someone was chosen from the phone's contacts: their number goes in (which
  /// also looks up a returning customer), and their name if none is typed yet.
  void _contactPicked(PickedContact contact) {
    setState(() {
      _mobile.text = contact.number;
      if (_name.text.trim().isEmpty) _name.text = contact.name;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CustomerInfo(
        name: _name.text,
        mobile: _mobile.text,
        nid: _nid.text,
        address: _address.text,
        // One number: the receipt and reminders go to it as WhatsApp, calls and SMS.
        whatsapp: _mobile.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(Bn.addCustomer),
        // Wider than the default (which leaves 40 on each side), so the fields have room.
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: SingleChildScrollView(
          // Room above the first field: its floating label rises above the box, and the
          // scroll view would cut it off.
          padding: const EdgeInsets.only(top: 8),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _mobile,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _label(Bn.customerPhone, required: true),
                    helperText: Bn.customerPhoneHelp,
                    helperMaxLines: 3,
                    prefixIcon: const Icon(Icons.chat_outlined),
                    suffixIcon: ContactPickButton(picker: widget.picker, onPicked: _contactPicked),
                  ),
                  validator: _numberError,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: _label(Bn.customerName, required: widget.dueRequired)),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: _label(Bn.customerAddress, required: widget.dueRequired)),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nid,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _label(Bn.customerNid, required: widget.dueRequired)),
                  validator: _nidError,
                ),
                if (_known)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      Bn.knownCustomer,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(Bn.cancel)),
          FilledButton(onPressed: _submit, child: Text(Bn.save)),
        ],
      );
}
