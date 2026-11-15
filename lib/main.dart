import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Chave publishable: foi feita para ficar no app. Nunca coloque aqui a chave secret.
const _url = 'https://lsaqihujwdzybucsfpcp.supabase.co';
const _key = 'sb_publishable_FZi9CphFqTjU-ifyFuQh1A_diPVVYgx';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _url, anonKey: _key);
  runApp(const App());
}

final db = Supabase.instance.client;

const statusNomes = {
  'novo': 'Novo',
  'encaminhado': 'Encaminhado',
  'em_negociacao': 'Em negociação',
  'fechado': 'Fechado',
  'perdido': 'Perdido',
};

String brl(num v) {
  final p = v.toStringAsFixed(2).split('.');
  final i = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $i,${p[1]}';
}

String dataBr(String iso) {
  final d = iso.substring(0, 10).split('-');
  return '${d[2]}/${d[1]}/${d[0]}';
}

num? lerNum(String s) => num.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

String paraTexto(num n) => n.toString().replaceAll('.', ',');

void aviso(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

Future<void> abrir(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Meus Leads',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1F5F5B), useMaterial3: true),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (_, __) =>
              db.auth.currentSession == null ? const LoginPage() : const HomePage(),
        ),
      );
}

// ---------------------------------------------------------------- Login
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final email = TextEditingController();
  final senha = TextEditingController();
  bool entrando = false;

  Future<void> entrar() async {
    setState(() => entrando = true);
    try {
      await db.auth.signInWithPassword(email: email.text.trim(), password: senha.text);
    } on AuthException catch (e) {
      if (mounted) aviso(context, 'Não foi possível entrar: ${e.message}');
    }
    if (mounted) setState(() => entrando = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(children: [
                const Text('Meus Leads', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: senha,
                  obscureText: true,
                  onSubmitted: (_) => entrar(),
                  decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: entrando ? null : entrar,
                  child: Text(entrando ? 'Entrando...' : 'Entrar'),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- Home
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  int aba = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(aba == 0 ? 'Leads' : 'Comissões'),
          actions: [
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => db.auth.signOut(),
            ),
          ],
        ),
        body: aba == 0 ? const LeadsTab() : const ComissoesTab(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: aba,
          onDestinationSelected: (i) => setState(() => aba = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people), label: 'Leads'),
            NavigationDestination(icon: Icon(Icons.payments), label: 'Comissões'),
          ],
        ),
      );
}

// ---------------------------------------------------------------- Leads
class LeadsTab extends StatefulWidget {
  const LeadsTab({super.key});
  @override
  State<LeadsTab> createState() => _LeadsState();
}

class _LeadsState extends State<LeadsTab> {
  List<Map<String, dynamic>>? leads;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    try {
      final r = await db
          .from('leads')
          .select('*, imoveis(nome, valor_base, percentual_comissao)')
          .order('criado_em', ascending: false);
      if (mounted) setState(() => leads = r);
    } catch (e) {
      if (mounted) {
        setState(() => leads = []);
        aviso(context, 'Erro ao carregar os leads: $e');
      }
    }
  }

  Future<void> mudarStatus(Map<String, dynamic> l, String s, [Map<String, dynamic> extra = const {}]) async {
    await db.from('leads').update({'status': s, ...extra}).eq('id', l['id']);
    carregar();
  }

  String fone(String t) {
    final d = t.replaceAll(RegExp(r'\D'), '');
    return d.length <= 11 ? '55$d' : d;
  }

  // Abre o WhatsApp com o resumo do lead; você escolhe o gerente na lista de contatos.
  Future<void> enviarGerente(Map<String, dynamic> l) async {
    final im = l['imoveis'];
    String campo(String k) => (l[k] ?? '').toString();
    final msg = [
      '*Novo lead*',
      'Nome: ${l['nome']}',
      'Telefone: ${l['telefone']}',
      if (im != null) 'Imóvel: ${im['nome']}',
      if (campo('origem').isNotEmpty) 'Origem: ${campo('origem')}',
      if (campo('faixa_valor').isNotEmpty) 'Faixa de valor: ${campo('faixa_valor')}',
      if (campo('observacoes').isNotEmpty) 'Obs: ${campo('observacoes')}',
    ].join('\n');
    await abrir('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    final retorno = DateTime.now().add(const Duration(days: 3)).toIso8601String().substring(0, 10);
    await mudarStatus(l, 'encaminhado', {
      'encaminhado_em': DateTime.now().toUtc().toIso8601String(),
      'proximo_retorno': retorno,
    });
  }

  Future<void> fecharVenda(Map<String, dynamic> l) async {
    final im = l['imoveis'];
    final valor = TextEditingController(text: im == null ? '' : paraTexto(im['valor_base']));
    final perc = TextEditingController(text: im == null ? '' : paraTexto(im['percentual_comissao']));
    const teclado = TextInputType.numberWithOptions(decimal: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final v = lerNum(valor.text), p = lerNum(perc.text);
        return AlertDialog(
          title: const Text('Venda fechada'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: valor,
              keyboardType: teclado,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(labelText: 'Valor real da venda (R\$)'),
            ),
            TextField(
              controller: perc,
              keyboardType: teclado,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(labelText: 'Comissão (%)'),
            ),
            const SizedBox(height: 16),
            Text(
              v != null && p != null ? 'Sua comissão: ${brl(v * p / 100)}' : '',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: v != null && p != null ? () => Navigator.pop(c, true) : null,
              child: const Text('Salvar venda'),
            ),
          ],
        );
      }),
    );
    if (ok != true) return;
    await db.from('comissoes').upsert({
      'lead_id': l['id'],
      'valor_venda': lerNum(valor.text),
      'percentual': lerNum(perc.text),
    }, onConflict: 'lead_id');
    await mudarStatus(l, 'fechado');
  }

  void acoes(Map<String, dynamic> l) {
    void fazer(BuildContext c, VoidCallback f) {
      Navigator.pop(c);
      f();
    }

    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(l['nome'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l['telefone']),
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Enviar ao gerente (WhatsApp)'),
              onTap: () => fazer(c, () => enviarGerente(l)),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Falar com o cliente'),
              onTap: () => fazer(c, () => abrir('https://wa.me/${fone(l['telefone'])}')),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Marcar em negociação'),
              onTap: () => fazer(c, () => mudarStatus(l, 'em_negociacao')),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text('Registrar venda fechada'),
              onTap: () => fazer(c, () => fecharVenda(l)),
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Marcar como perdido'),
              onTap: () => fazer(c, () => mudarStatus(l, 'perdido')),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Novo lead'),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadForm()));
            carregar();
          },
        ),
        body: leads == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: carregar,
                child: leads!.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nenhum lead ainda. Toque em Novo lead para cadastrar o primeiro.')),
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: leads!.length,
                        itemBuilder: (_, i) {
                          final l = leads![i];
                          final im = l['imoveis'];
                          final detalhes = [
                            if (im != null) im['nome'],
                            if (l['status'] == 'encaminhado' && l['proximo_retorno'] != null)
                              'cobrar retorno em ${dataBr(l['proximo_retorno'])}',
                          ].join(' · ');
                          return ListTile(
                            title: Text(l['nome']),
                            subtitle: detalhes.isEmpty ? null : Text(detalhes),
                            trailing: Chip(label: Text(statusNomes[l['status']] ?? l['status'])),
                            onTap: () => acoes(l),
                          );
                        },
                      ),
              ),
      );
}

// ---------------------------------------------------------------- Novo lead
class LeadForm extends StatefulWidget {
  const LeadForm({super.key});
  @override
  State<LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends State<LeadForm> {
  final nome = TextEditingController();
  final tel = TextEditingController();
  final origem = TextEditingController();
  final faixa = TextEditingController();
  final obs = TextEditingController();
  List<Map<String, dynamic>> imoveis = [];
  Map<String, dynamic>? imovel;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    db.from('imoveis').select().eq('ativo', true).order('nome').then((r) {
      if (mounted) setState(() => imoveis = r);
    });
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty || tel.text.trim().isEmpty) {
      aviso(context, 'Preencha o nome e o telefone.');
      return;
    }
    setState(() => salvando = true);
    try {
      await db.from('leads').insert({
        'nome': nome.text.trim(),
        'telefone': tel.text.trim(),
        'origem': origem.text.trim(),
        'imovel_id': imovel?['id'],
        'faixa_valor': faixa.text.trim(),
        'observacoes': obs.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => salvando = false);
        aviso(context, 'Erro ao salvar: $e');
      }
    }
  }

  Widget campo(String rotulo, TextEditingController c, {TextInputType? teclado, int linhas = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          maxLines: linhas,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Novo lead')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          campo('Nome', nome),
          campo('Telefone (com DDD)', tel, teclado: TextInputType.phone),
          campo('Origem (anúncio, indicação, Instagram...)', origem),
          DropdownButtonFormField<Map<String, dynamic>>(
            value: imovel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Imóvel de interesse', border: OutlineInputBorder()),
            items: [
              for (final i in imoveis)
                DropdownMenuItem(value: i, child: Text(i['nome'], overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => imovel = v),
          ),
          if (imovel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Comissão estimada: ${brl(imovel!['valor_base'] * imovel!['percentual_comissao'] / 100)} '
                '(${paraTexto(imovel!['percentual_comissao'])}%)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 12),
          campo('Faixa de valor', faixa),
          campo('Observações', obs, linhas: 3),
          FilledButton(
            onPressed: salvando ? null : salvar,
            child: Text(salvando ? 'Salvando...' : 'Salvar lead'),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- Comissões
class ComissoesTab extends StatefulWidget {
  const ComissoesTab({super.key});
  @override
  State<ComissoesTab> createState() => _ComissoesState();
}

class _ComissoesState extends State<ComissoesTab> {
  List<Map<String, dynamic>>? itens;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    try {
      final r = await db.from('comissoes').select('*, leads(nome)').order('data_fechamento', ascending: false);
      if (mounted) setState(() => itens = r);
    } catch (e) {
      if (mounted) {
        setState(() => itens = []);
        aviso(context, 'Erro ao carregar as comissões: $e');
      }
    }
  }

  num soma(String status) =>
      itens!.where((c) => c['status'] == status).fold<num>(0, (a, c) => a + (c['valor_comissao'] as num));

  Future<void> alternar(Map<String, dynamic> c) async {
    final recebida = c['status'] == 'recebida';
    await db.from('comissoes').update({
      'status': recebida ? 'a_receber' : 'recebida',
      'data_recebimento': recebida ? null : DateTime.now().toIso8601String().substring(0, 10),
    }).eq('id', c['id']);
    carregar();
  }

  Widget total(String titulo, num valor) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo),
              const SizedBox(height: 4),
              Text(brl(valor), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (itens == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [total('A receber', soma('a_receber')), total('Recebido', soma('recebida'))]),
        ),
        if (itens!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nenhuma venda registrada. Feche um lead para ver a comissão aqui.')),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Toque em uma comissão para marcar como recebida.'),
          ),
        for (final c in itens!)
          ListTile(
            title: Text(c['leads']?['nome'] ?? 'Lead removido'),
            subtitle: Text('${dataBr(c['data_fechamento'])} · venda ${brl(c['valor_venda'])} · ${paraTexto(c['percentual'])}%'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(brl(c['valor_comissao']), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(c['status'] == 'recebida' ? 'Recebida' : 'A receber'),
            ]),
            onTap: () => alternar(c),
          ),
      ]),
    );
  }
}
