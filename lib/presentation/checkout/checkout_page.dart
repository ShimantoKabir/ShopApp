import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customer_rules.dart';
import '../../domain/sales.dart';
import '../../domain/services.dart';
import '../../domain/stock.dart';
import '../../domain/sync.dart';
import '../components/components.dart';
import '../labels.dart';
import '../screen_factory.dart';
import '../sell/sell_viewmodel.dart';
import '../widgets/contact_pick_button.dart';

/// Review the cart, take the customer's details, and say how much was paid.
///
/// The customer section is always there, but small while the sale is paid in
/// full: tap it to open it and take their details when the shop is quiet (all
/// optional). When something is left unpaid (the "paid in full" switch is off)
/// it opens by itself and the name, one number (ask for their WhatsApp number,
/// so the receipt and reminders can go there), NID and address are required. Uses the sell screen's [viewModel]
/// (it owns the cart); this page does not dispose it.
class CheckoutPage extends StatefulWidget {
  final SellViewModel viewModel;
  final ScreenFactory screens;

  /// When given, the number field offers "choose from contacts".
  final ContactPicker? contactPicker;
  const CheckoutPage({super.key, required this.viewModel, required this.screens, this.contactPicker});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  SellViewModel get _vm => widget.viewModel;

  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _nid = TextEditingController();
  final _paid = TextEditingController();

  bool _paidInFull = true;

  /// The person opened the customer section while it is optional.
  bool _opened = false;

  /// Open for a due (required), or when the person opened it.
  bool get _customerOpen => !_paidInFull || _opened;
  bool _knownCustomer = false;
  bool _saving = false;
  bool _attempted = false; // has "confirm" been pressed yet?
  bool _wasDueRequired = false;
  final Set<String> _lookedUp = {};

  double get _paidAmount => _paidInFull ? _vm.cartTotal : (parseNumber(_paid.text) ?? 0);
  double get _due {
    final rest = _vm.cartTotal - _paidAmount;
    return rest < stockEpsilon ? 0 : rest;
  }

  bool get _dueRequired => _due > 0;

  @override
  void initState() {
    super.initState();
    _paid.addListener(_paymentChanged);
    _mobile.addListener(() => _lookUpCustomer(_mobile.text));
    _vm.addListener(_cartChanged);
    _catchUp(); // before taking payment: has another phone sold any of this?
  }

  Future<void> _catchUp() async {
    final shortages = await _vm.refreshFromShop();
    if (!mounted || shortages.isEmpty) return;
    _say(shortages.map((s) => Bn.stockChangedElsewhere(s.name, s.left)).join('\n'));
  }

  @override
  void dispose() {
    _vm.removeListener(_cartChanged);
    for (final c in [_address, _name, _mobile, _nid, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The amount paid (or the switch) changed: the due, and with it whether the
  /// name/mobile/NID are required, may have changed too.
  void _paymentChanged() {
    setState(() {});
    _refreshErrorsIfRequirementChanged();
  }

  /// After a failed confirm, errors on those fields must follow the
  /// requirement: they appear when it starts, and go when it ends.
  void _refreshErrorsIfRequirementChanged() {
    final required = _dueRequired;
    if (_attempted && required != _wasDueRequired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _formKey.currentState?.validate());
    }
    _wasDueRequired = required;
  }

  /// Removing the last item leaves nothing to check out.
  void _cartChanged() {
    if (mounted && _vm.cartCount == 0 && !_saving) Navigator.maybePop(context);
  }

  /// A repeat customer: fill in what we already know (never over what was typed).
  Future<void> _lookUpCustomer(String typed) async {
    final number = normalizeMobile(typed);
    if (!isValidMobile(number) || !_lookedUp.add(number)) return;
    final known = await _vm.findCustomer(number);
    if (!mounted || known == null) return;
    void fill(TextEditingController c, String value) {
      if (c.text.trim().isEmpty && value.isNotEmpty) c.text = value;
    }

    setState(() {
      _knownCustomer = true;
      fill(_name, known.name);
      fill(_address, known.address);
      fill(_nid, known.nid);
      fill(_mobile, known.whatsapp.isNotEmpty ? known.whatsapp : known.mobile);
    });
  }

  /// Someone was chosen from the phone's contacts: their number goes in (which
  /// also looks up a returning customer), and their name if none is typed yet.
  void _contactPicked(PickedContact contact) {
    setState(() {
      _mobile.text = contact.number;
      if (_name.text.trim().isEmpty) _name.text = contact.name;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _addressError(String? v) => (_dueRequired && (v ?? '').trim().isEmpty) ? Bn.requiredForDue : null;

  String? _nameError(String? v) => (_dueRequired && (v ?? '').trim().isEmpty) ? Bn.requiredForDue : null;

  String? _mobileError(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return _dueRequired ? Bn.requiredForDue : null;
    return isValidMobile(text) ? null : Bn.mobileInvalid;
  }

  String? _nidError(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return _dueRequired ? Bn.requiredForDue : null;
    return isValidNid(text) ? null : Bn.nidInvalid;
  }

  String? _paidError(String? v) {
    if ((v ?? '').trim().isEmpty) return null; // nothing paid yet: all of it is due
    final n = parseNumber(v);
    if (n == null) return Bn.invalidNumber;
    return n > _vm.cartTotal + stockEpsilon ? Bn.paidTooMuch : null;
  }

  Future<void> _submit() async {
    _attempted = true;
    _wasDueRequired = _dueRequired;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final bill = await _vm.checkout(
        // What is in the section is only sent while it is open.
        customer: !_customerOpen
            ? null
            : CustomerInfo(
          name: _name.text,
          mobile: _mobile.text,
          nid: _nid.text,
          address: _address.text,
          // One number: the receipt and reminders go to it as WhatsApp, calls and SMS.
          whatsapp: _mobile.text,
        ),
        paid: _paidInFull ? null : _paidAmount,
      );
      if (!mounted) return;
      // Replace this page with the receipt, so "done" returns to the sell screen.
      await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => widget.screens.receipt(bill)));
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _say(message);
      // Recorded, just not seen back yet: nothing left to do on this page.
      if (e is SyncException && e.problem == SyncProblem.delayed && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changeQuantity(CartLine line, double by) {
    try {
      _vm.setQuantity(line, line.quantity + by);
    } on StockException catch (e) {
      _say(stockProblemMessage(e.problem));
    }
  }

  /// A star on the label when the field is required.
  String _label(String base, {bool required = true}) => required ? '$base *' : base;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.checkoutTitle)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Form(
            key: _formKey,
            // Errors update as the user types, so a fixed field stops being red at once.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: Bn.cartLines,
                  icon: Icons.shopping_cart_outlined,
                  children: [
                    for (final line in List.of(_vm.cart)) _lineRow(line),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(Bn.saleTotal, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          formatMoney(_vm.cartTotal),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: Bn.paymentSection,
                  icon: Icons.payments_outlined,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(Bn.paidInFull),
                      value: _paidInFull,
                      onChanged: (v) {
                        setState(() => _paidInFull = v);
                        _refreshErrorsIfRequirementChanged();
                      },
                    ),
                    if (!_paidInFull) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _paid,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9০-৯.,।]'))],
                        decoration: InputDecoration(labelText: Bn.paidAmount, prefixText: '${Bn.taka} '),
                        validator: _paidError,
                      ),
                      if (_due > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${Bn.dueLabel}: ${formatMoney(_due)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        // While a due makes it required it stays open; otherwise it opens and closes.
                        onTap: _paidInFull ? () => setState(() => _opened = !_opened) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.person_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      Bn.customerSection,
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (!_customerOpen)
                                      Text(
                                        Bn.customerOptionalHint,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_paidInFull) Icon(_opened ? Icons.expand_less : Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                      if (_customerOpen)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                    TextFormField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _label(Bn.customerPhone, required: _dueRequired),
                        helperText: Bn.customerPhoneHelp,
                        helperMaxLines: 3,
                        prefixIcon: const Icon(Icons.chat_outlined),
                        suffixIcon: ContactPickButton(picker: widget.contactPicker, onPicked: _contactPicked),
                      ),
                      validator: _mobileError,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: _label(Bn.customerName, required: _dueRequired)),
                      validator: _nameError,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 3,
                      keyboardType: TextInputType.streetAddress,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: _label(Bn.customerAddress, required: _dueRequired)),
                      validator: _addressError,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nid,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _label(Bn.customerNid, required: _dueRequired)),
                      validator: _nidError,
                    ),
                    const SizedBox(height: 8),
                    if (_knownCustomer)
                      Padding(padding: EdgeInsets.only(bottom: 4), child: InfoChip(label: Bn.knownCustomer, icon: Icons.history)),
                    Text(
                      Bn.customerNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ActionButtonRow(primaryLabel: Bn.confirmSale, onPrimary: _submit, busy: _saving),
              ],
            ),
          ),
        ),
      );

  Widget _lineRow(CartLine line) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name, style: theme.textTheme.titleSmall),
                Text(
                  '${formatMoney(line.unitPrice)} / ${Bn.unitName(line.product.unit)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _changeQuantity(line, -1),
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: Bn.removeFromCart,
          ),
          Text('${formatNumber(line.quantity)} ${Bn.unitName(line.product.unit)}', style: theme.textTheme.titleSmall),
          IconButton(onPressed: () => _changeQuantity(line, 1), icon: const Icon(Icons.add_circle_outline)),
          SizedBox(width: 72, child: Text(formatMoney(line.total), textAlign: TextAlign.end, style: theme.textTheme.titleSmall)),
        ],
      ),
    );
  }
}
