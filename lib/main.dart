import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'imagens.dart';

// Chave publishable: foi feita para ficar no app. Nunca coloque aqui a chave secret.
const _url = 'https://lsaqihujwdzybucsfpcp.supabase.co';
const _key = 'sb_publishable_FZi9CphFqTjU-ifyFuQh1A_diPVVYgx';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _url, anonKey: _key);
  await Lembretes.iniciar();
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

const petroleo = Color(0xFF1F5F5B);
const verde = Color(0xFF2E7D32);
const laranja = Color(0xFFE65100);
const azul = Color(0xFF1565C0);
const roxo = Color(0xFF6A1B9A);

const statusCores = {
  'novo': azul,
  'encaminhado': laranja,
  'em_negociacao': roxo,
  'fechado': verde,
  'perdido': Color(0xFFC62828),
};

Color corStatus(String s) => statusCores[s] ?? const Color(0xFF546E7A);

final _fotos = <String, Uint8List>{};

// "Logo" do imóvel: a miniatura do PDF (se o nome combina) ou um ícone de casa.
Widget logoImovel(String nome, {double tamanho = 64}) {
  final n = nome.toLowerCase();
  String? chave;
  for (final k in imagensImoveis.keys) {
    if (n.contains(k)) {
      chave = k;
      break;
    }
  }
  if (chave == null) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: petroleo.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.home_work, color: petroleo),
    );
  }
  final k = chave;
  final bytes = _fotos.putIfAbsent(k, () => base64Decode(imagensImoveis[k]!));
  return Container(
    width: tamanho,
    height: tamanho,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: petroleo.withValues(alpha: .3), width: 1.5),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12.5),
      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    ),
  );
}

Widget etiqueta(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: .35)),
      ),
      child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
    );

Future<void> abrir(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

// ---------------------------------------------------------------- Ficha de passagem
const opcoesCanal = ['indicação', 'marketplace', 'redes', 'PAP', 'ligação', 'outro'];
const opcoesMoraHoje = {'aluguel': 'Aluguel', 'com_os_pais': 'Com os pais', 'outro': 'Outro'};
const opcoesTipoRenda = {'carteira': 'Carteira', 'autonomo': 'Autônomo', 'outro': 'Outro'};
const opcoesRestricao = {'sim': 'Sim', 'nao': 'Não', 'nao_sabe': 'Não sabe'};

String numTexto(dynamic v) => v == null ? '' : paraTexto(v as num);
String dinheiro(dynamic v) => v == null ? '—' : brl(v as num);
String simNaoTexto(dynamic v) => v == null ? '—' : (v == true ? 'Sim' : 'Não');

String vazio(dynamic v) {
  final t = (v ?? '').toString().trim();
  return t.isEmpty ? '—' : t;
}

String dataHoraBr(DateTime d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  final hora = '${d.hour}h${d.minute == 0 ? '' : dois(d.minute)}';
  return '${dois(d.day)}/${dois(d.month)} às $hora';
}

// Mensagem enviada ao gerente, com os mesmos campos da ficha.
String fichaTexto(Map<String, dynamic> l) {
  final im = l['imoveis'];
  final titulo = im == null
      ? 'FICHA DE PASSAGEM'
      : 'FICHA DE PASSAGEM – ${im['nome'].toString().toUpperCase()}';
  final aluguel = l['mora_hoje'] == 'aluguel' ? ' – valor do aluguel: ${dinheiro(l['valor_aluguel'])}' : '';
  final fgts = l['tem_fgts'] == true ? 'Sim – aprox. ${dinheiro(l['valor_fgts'])}' : simNaoTexto(l['tem_fgts']);
  final entrada = l['tem_entrada'] == true ? 'Sim – ${dinheiro(l['valor_entrada'])}' : simNaoTexto(l['tem_entrada']);
  final quando = l['atendimento_em'] == null
      ? '—'
      : 'dia ${dataHoraBr(DateTime.parse(l['atendimento_em'].toString()).toLocal())}';
  final obs = vazio(l['observacoes']);
  return [
    '*$titulo*',
    '',
    '*Consultor:* ${vazio(l['consultor'])}',
    '*Cliente:* ${vazio(l['nome'])}',
    '*Telefone:* ${vazio(l['telefone'])}',
    '*Canal de origem:* ${vazio(l['origem'])}',
    '',
    '*Quem vai morar:* ${vazio(l['quem_vai_morar'])}',
    '*Mora hoje:* ${opcoesMoraHoje[l['mora_hoje']] ?? '—'}$aluguel',
    '*Renda familiar:* ${dinheiro(l['renda_familiar'])} – quem compõe: ${vazio(l['quem_compoe_renda'])}',
    '*Tipo de renda:* ${opcoesTipoRenda[l['tipo_renda']] ?? '—'}',
    '*Tem FGTS?* $fgts',
    '*Nome com restrição?* ${opcoesRestricao[l['nome_restrito']] ?? '—'}',
    '*Já teve imóvel financiado?* ${simNaoTexto(l['ja_teve_financiamento'])}',
    '*Tem valor para entrada?* $entrada',
    '',
    '*O que ele mais quer na casa:* ${vazio(l['o_que_quer_na_casa'])}',
    '*O que fez procurar agora:* ${vazio(l['motivo_procura'])}',
    '*Quem decide junto:* ${vazio(l['quem_decide_junto'])}',
    '*Atendimento agendado:* $quando',
    '*Confirmado no dia?* ${simNaoTexto(l['confirmado_no_dia'])}',
    if (obs != '—') ...['', '*Observações:* $obs'],
  ].join('\n');
}

// Abre o WhatsApp com a ficha (você escolhe o contato do gerente) e marca o lead como encaminhado.
Future<void> enviarFicha(Map<String, dynamic> l) async {
  await abrir('https://wa.me/?text=${Uri.encodeComponent(fichaTexto(l))}');
  final retorno = DateTime.now().add(const Duration(days: 3)).toIso8601String().substring(0, 10);
  await db.from('leads').update({
    'status': 'encaminhado',
    'encaminhado_em': DateTime.now().toUtc().toIso8601String(),
    if (l['proximo_retorno'] == null) 'proximo_retorno': retorno,
  }).eq('id', l['id']);
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Meus Leads',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: petroleo,
          useMaterial3: true,
          cardTheme: CardThemeData(
            elevation: 0,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: petroleo.withValues(alpha: .22)),
            ),
          ),
        ),
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
          title: Text(const ['Leads', 'Comissões', 'Imóveis', 'Relatórios'][aba]),
          actions: [
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => db.auth.signOut(),
            ),
          ],
        ),
        body: const [LeadsTab(), ComissoesTab(), ImoveisTab(), RelatoriosTab()][aba],
        bottomNavigationBar: NavigationBar(
          selectedIndex: aba,
          onDestinationSelected: (i) => setState(() => aba = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people), label: 'Leads'),
            NavigationDestination(icon: Icon(Icons.payments), label: 'Comissões'),
            NavigationDestination(icon: Icon(Icons.home_work), label: 'Imóveis'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Relatórios'),
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
      Lembretes.sincronizar(r);
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

  Future<void> enviarGerente(Map<String, dynamic> l) async {
    await enviarFicha(l);
    carregar();
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

  Future<void> excluir(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir lead?'),
        content: Text('${l['nome']} será apagado. Se houver comissão registrada para ele, ela também será apagada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await db.from('leads').delete().eq('id', l['id']);
    carregar();
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
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar lead'),
              onTap: () => fazer(c, () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => LeadForm(lead: l)));
                carregar();
              }),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Excluir lead'),
              onTap: () => fazer(c, () => excluir(l)),
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
                        padding: const EdgeInsets.only(top: 8, bottom: 88),
                        itemCount: leads!.length,
                        itemBuilder: (_, i) {
                          final l = leads![i];
                          final im = l['imoveis'];
                          final detalhes = [
                            if (im != null) im['nome'],
                            if (l['proximo_retorno'] != null && l['status'] != 'fechado' && l['status'] != 'perdido')
                              'cobrar retorno em ${dataBr(l['proximo_retorno'])}',
                            if (l['atendimento_em'] != null)
                              'atendimento ${dataHoraBr(DateTime.parse(l['atendimento_em'].toString()).toLocal())}',
                          ].join(' · ');
                          final cor = corStatus(l['status']);
                          final nomeLead = l['nome'].toString().trim();
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cor.withValues(alpha: .14),
                                child: Text(
                                  nomeLead.isEmpty ? '?' : nomeLead[0].toUpperCase(),
                                  style: TextStyle(color: cor, fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(l['nome'], style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: detalhes.isEmpty ? null : Text(detalhes),
                              trailing: etiqueta(statusNomes[l['status']] ?? l['status'], cor),
                              onTap: () => acoes(l),
                            ),
                          );
                        },
                      ),
              ),
      );
}

// ---------------------------------------------------------------- Novo lead
class LeadForm extends StatefulWidget {
  final Map<String, dynamic>? lead;
  const LeadForm({super.key, this.lead});
  @override
  State<LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends State<LeadForm> {
  Map<String, dynamic> get l => widget.lead ?? const {};

  late final consultor = TextEditingController(
    text: l['consultor'] ?? db.auth.currentUser?.userMetadata?['consultor'],
  );
  late final nome = TextEditingController(text: l['nome']);
  late final tel = TextEditingController(text: l['telefone']);
  late final quemMora = TextEditingController(text: l['quem_vai_morar']);
  late final aluguel = TextEditingController(text: numTexto(l['valor_aluguel']));
  late final renda = TextEditingController(text: numTexto(l['renda_familiar']));
  late final quemCompoe = TextEditingController(text: l['quem_compoe_renda']);
  late final fgts = TextEditingController(text: numTexto(l['valor_fgts']));
  late final entrada = TextEditingController(text: numTexto(l['valor_entrada']));
  late final querNaCasa = TextEditingController(text: l['o_que_quer_na_casa']);
  late final motivo = TextEditingController(text: l['motivo_procura']);
  late final quemDecide = TextEditingController(text: l['quem_decide_junto']);
  late final obs = TextEditingController(text: l['observacoes']);
  late String? canal = l['origem'];
  late String? moraHoje = l['mora_hoje'];
  late String? tipoRenda = l['tipo_renda'];
  late String? restricao = l['nome_restrito'];
  late bool? temFgts = l['tem_fgts'];
  late bool? jaFinanciou = l['ja_teve_financiamento'];
  late bool? temEntrada = l['tem_entrada'];
  late bool? confirmado = l['confirmado_no_dia'];
  late DateTime? atendimento =
      l['atendimento_em'] == null ? null : DateTime.parse(l['atendimento_em'].toString()).toLocal();
  late String? retorno = l['proximo_retorno'];
  List<Map<String, dynamic>> imoveis = [];
  Map<String, dynamic>? imovel;
  bool salvando = false;

  static const _decimal = TextInputType.numberWithOptions(decimal: true);
  static const _simNao = {true: 'Sim', false: 'Não'};

  @override
  void initState() {
    super.initState();
    db.from('imoveis').select().order('nome').then((r) {
      if (!mounted) return;
      final atual = l['imovel_id'];
      setState(() {
        imoveis = r.where((i) => i['ativo'] == true || i['id'] == atual).toList();
        imovel = imoveis.where((i) => i['id'] == atual).firstOrNull;
      });
    });
  }

  Map<String, dynamic> dados() => {
        'consultor': consultor.text.trim(),
        'nome': nome.text.trim(),
        'telefone': tel.text.trim(),
        'origem': canal,
        'imovel_id': imovel?['id'],
        'quem_vai_morar': quemMora.text.trim(),
        'mora_hoje': moraHoje,
        'valor_aluguel': moraHoje == 'aluguel' ? lerNum(aluguel.text) : null,
        'renda_familiar': lerNum(renda.text),
        'quem_compoe_renda': quemCompoe.text.trim(),
        'tipo_renda': tipoRenda,
        'tem_fgts': temFgts,
        'valor_fgts': temFgts == true ? lerNum(fgts.text) : null,
        'nome_restrito': restricao,
        'ja_teve_financiamento': jaFinanciou,
        'tem_entrada': temEntrada,
        'valor_entrada': temEntrada == true ? lerNum(entrada.text) : null,
        'o_que_quer_na_casa': querNaCasa.text.trim(),
        'motivo_procura': motivo.text.trim(),
        'quem_decide_junto': quemDecide.text.trim(),
        'atendimento_em': atendimento?.toUtc().toIso8601String(),
        'confirmado_no_dia': confirmado,
        'observacoes': obs.text.trim(),
        'proximo_retorno': retorno,
      };

  // Guarda o nome do consultor na conta, para já vir preenchido nos próximos leads.
  Future<void> lembrarConsultor(String c) async {
    try {
      if (c.isNotEmpty && c != db.auth.currentUser?.userMetadata?['consultor']) {
        await db.auth.updateUser(UserAttributes(data: {'consultor': c}));
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> salvar() async {
    if (nome.text.trim().isEmpty || tel.text.trim().isEmpty) {
      aviso(context, 'Preencha o nome do cliente e o telefone.');
      return null;
    }
    setState(() => salvando = true);
    try {
      const sel = '*, imoveis(nome, valor_base, percentual_comissao)';
      final Map<String, dynamic> r = widget.lead == null
          ? await db.from('leads').insert(dados()).select(sel).single()
          : await db.from('leads').update(dados()).eq('id', widget.lead!['id']).select(sel).single();
      lembrarConsultor(consultor.text.trim());
      return r;
    } catch (e) {
      if (mounted) {
        setState(() => salvando = false);
        aviso(context, 'Erro ao salvar: $e');
      }
      return null;
    }
  }

  Future<void> escolherAtendimento() async {
    final base = atendimento ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (h == null) return;
    setState(() => atendimento = DateTime(d.year, d.month, d.day, h.hour, h.minute));
  }

  Widget secao(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Text(
          titulo,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: petroleo, fontWeight: FontWeight.w700),
        ),
      );

  Widget campo(String rotulo, TextEditingController c,
          {TextInputType? teclado, int linhas = 1, String? prefixo}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          maxLines: linhas,
          textCapitalization: teclado == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: rotulo, prefixText: prefixo, border: const OutlineInputBorder()),
        ),
      );

  Widget lista(String rotulo, Map<String, String> opcoes, String? valor, ValueChanged<String?> mudou) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
          items: [for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: mudou,
        ),
      );

  Widget escolha<T extends Object>(String rotulo, Map<T, String> opcoes, T? valor, ValueChanged<T?> mudou) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [for (final e in opcoes.entries) ButtonSegment<T>(value: e.key, label: Text(e.value))],
              selected: valor == null ? <T>{} : {valor},
              onSelectionChanged: (s) => mudou(s.isEmpty ? null : s.first),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final canais = [...opcoesCanal, if (canal != null && !opcoesCanal.contains(canal)) canal!];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lead == null ? 'Ficha de passagem' : 'Editar ficha')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        secao('Contato'),
        campo('Consultor', consultor),
        campo('Cliente', nome),
        campo('Telefone (com DDD)', tel, teclado: TextInputType.phone),
        lista('Canal de origem', {for (final c in canais) c: c[0].toUpperCase() + c.substring(1)}, canal,
            (v) => setState(() => canal = v)),
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
        secao('Perfil da família'),
        campo('Quem vai morar', quemMora),
        lista('Mora hoje', opcoesMoraHoje, moraHoje, (v) => setState(() => moraHoje = v)),
        if (moraHoje == 'aluguel') campo('Valor do aluguel', aluguel, teclado: _decimal, prefixo: 'R\$ '),
        campo('Renda familiar', renda, teclado: _decimal, prefixo: 'R\$ '),
        campo('Quem compõe a renda', quemCompoe),
        lista('Tipo de renda', opcoesTipoRenda, tipoRenda, (v) => setState(() => tipoRenda = v)),
        escolha<bool>('Tem FGTS?', _simNao, temFgts, (v) => setState(() => temFgts = v)),
        if (temFgts == true) campo('Quanto de FGTS (aproximado)', fgts, teclado: _decimal, prefixo: 'R\$ '),
        escolha<String>('Nome com restrição?', opcoesRestricao, restricao, (v) => setState(() => restricao = v)),
        escolha<bool>('Já teve imóvel financiado?', _simNao, jaFinanciou, (v) => setState(() => jaFinanciou = v)),
        escolha<bool>('Tem valor para entrada?', _simNao, temEntrada, (v) => setState(() => temEntrada = v)),
        if (temEntrada == true) campo('Valor da entrada', entrada, teclado: _decimal, prefixo: 'R\$ '),
        secao('Interesse'),
        campo('O que ele mais quer na casa', querNaCasa, linhas: 2),
        campo('O que fez procurar agora', motivo, linhas: 2),
        campo('Quem decide junto', quemDecide),
        secao('Atendimento'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available),
          title: Text(atendimento == null ? 'Agendar atendimento' : 'Atendimento: dia ${dataHoraBr(atendimento!)}'),
          trailing: atendimento == null
              ? null
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => atendimento = null)),
          onTap: escolherAtendimento,
        ),
        escolha<bool>('Confirmado no dia?', _simNao, confirmado, (v) => setState(() => confirmado = v)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_active),
          title: Text(retorno == null ? 'Definir próximo retorno (lembrete)' : 'Retorno em ${dataBr(retorno!)}'),
          trailing: retorno == null
              ? null
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => retorno = null)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: retorno == null ? DateTime.now() : DateTime.parse(retorno!),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => retorno = d.toIso8601String().substring(0, 10));
          },
        ),
        const SizedBox(height: 8),
        campo('Observações (opcional)', obs, linhas: 3),
        FilledButton(
          onPressed: salvando
              ? null
              : () async {
                  final r = await salvar();
                  if (r != null && mounted) Navigator.pop(context);
                },
          child: Text(salvando ? 'Salvando...' : 'Salvar lead'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: salvando
              ? null
              : () async {
                  final r = await salvar();
                  if (r == null) return;
                  await enviarFicha(r);
                  if (mounted) Navigator.pop(context);
                },
          icon: const Icon(Icons.send),
          label: const Text('Salvar e enviar ao gerente'),
        ),
      ]),
    );
  }
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

  Widget total(String titulo, num valor, Color cor, IconData icone) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cor.withValues(alpha: .3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 6),
              Text(titulo, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Text(brl(valor), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cor)),
          ]),
        ),
      );

  Widget item(Map<String, dynamic> c) {
    final recebida = c['status'] == 'recebida';
    final cor = recebida ? verde : laranja;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cor.withValues(alpha: .14),
          child: Icon(recebida ? Icons.check : Icons.schedule, color: cor),
        ),
        title: Text(c['leads']?['nome'] ?? 'Lead removido', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${dataBr(c['data_fechamento'])} · venda ${brl(c['valor_venda'])} · ${paraTexto(c['percentual'])}%'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(brl(c['valor_comissao']), style: TextStyle(fontWeight: FontWeight.w700, color: cor)),
          Text(recebida ? 'Recebida' : 'A receber', style: TextStyle(color: cor, fontSize: 12)),
        ]),
        onTap: () => alternar(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (itens == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            total('A receber', soma('a_receber'), laranja, Icons.schedule),
            const SizedBox(width: 10),
            total('Recebido', soma('recebida'), verde, Icons.check_circle),
          ]),
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
        for (final c in itens!) item(c),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Imóveis
class ImoveisTab extends StatefulWidget {
  const ImoveisTab({super.key});
  @override
  State<ImoveisTab> createState() => _ImoveisState();
}

class _ImoveisState extends State<ImoveisTab> {
  List<Map<String, dynamic>>? itens;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    try {
      final r = await db.from('imoveis').select().order('nome');
      if (mounted) setState(() => itens = r);
    } catch (e) {
      if (mounted) {
        setState(() => itens = []);
        aviso(context, 'Erro ao carregar os imóveis: $e');
      }
    }
  }

  Future<void> editar([Map<String, dynamic>? im]) async {
    final nome = TextEditingController(text: im?['nome']);
    final local = TextEditingController(text: im?['localizacao']);
    final valor = TextEditingController(text: im == null ? '' : paraTexto(im['valor_base']));
    final perc = TextEditingController(text: im == null ? '' : paraTexto(im['percentual_comissao']));
    bool ativo = im?['ativo'] ?? true;
    const teclado = TextInputType.numberWithOptions(decimal: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(im == null ? 'Novo imóvel' : 'Editar imóvel'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(controller: local, decoration: const InputDecoration(labelText: 'Localização')),
              TextField(
                controller: valor,
                keyboardType: teclado,
                decoration: const InputDecoration(labelText: 'Valor base (R\$)'),
              ),
              TextField(
                controller: perc,
                keyboardType: teclado,
                decoration: const InputDecoration(labelText: 'Comissão (%)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disponível para novos leads'),
                value: ativo,
                onChanged: (v) => set(() => ativo = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = lerNum(valor.text), p = lerNum(perc.text);
    if (nome.text.trim().isEmpty || v == null || p == null) {
      if (mounted) aviso(context, 'Preencha nome, valor e percentual.');
      return;
    }
    final dados = {
      'nome': nome.text.trim(),
      'localizacao': local.text.trim(),
      'valor_base': v,
      'percentual_comissao': p,
      'ativo': ativo,
    };
    if (im == null) {
      await db.from('imoveis').insert(dados);
    } else {
      await db.from('imoveis').update(dados).eq('id', im['id']);
    }
    carregar();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Novo imóvel'),
          onPressed: () => editar(),
        ),
        body: itens == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: carregar,
                child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                  if (itens!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Nenhum imóvel cadastrado.')),
                    ),
                  for (final i in itens!)
                    Card(
                      child: ListTile(
                        leading: logoImovel(i['nome'].toString()),
                        title: Text(i['nome'], style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if ((i['localizacao'] ?? '').toString().isNotEmpty) i['localizacao'],
                          brl(i['valor_base']),
                        ].join(' · ')),
                        trailing: i['ativo'] == true
                            ? etiqueta('${paraTexto(i['percentual_comissao'])}%', verde)
                            : etiqueta('Inativo', const Color(0xFF546E7A)),
                        onTap: () => editar(i),
                      ),
                    ),
                ]),
              ),
      );
}

// ---------------------------------------------------------------- Relatórios
class RelatoriosTab extends StatefulWidget {
  const RelatoriosTab({super.key});
  @override
  State<RelatoriosTab> createState() => _RelatoriosState();
}

class _RelatoriosState extends State<RelatoriosTab> {
  List<Map<String, dynamic>>? leads;
  List<Map<String, dynamic>>? vendas;
  String periodo = 'mes';

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    try {
      final l = await db.from('leads').select('origem, status, data_atendimento, encaminhado_em');
      final v = await db.from('comissoes').select('valor_comissao, status, data_fechamento');
      if (mounted) {
        setState(() {
          leads = l;
          vendas = v;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          leads = [];
          vendas = [];
        });
        aviso(context, 'Erro ao carregar os relatórios: $e');
      }
    }
  }

  DateTime data(dynamic iso) => DateTime.parse(iso.toString().substring(0, 10));

  bool dentro(dynamic iso) {
    final d = data(iso);
    final hoje = DateTime.now();
    if (periodo == 'mes') return d.year == hoje.year && d.month == hoje.month;
    if (periodo == '30d') {
      return !d.isBefore(DateTime(hoje.year, hoje.month, hoje.day).subtract(const Duration(days: 30)));
    }
    return true;
  }

  Widget kpi(String titulo, String valor, Color cor, IconData icone) => SizedBox(
        width: 160,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cor.withValues(alpha: .3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 6),
              Expanded(child: Text(titulo, style: TextStyle(color: cor, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cor)),
          ]),
        ),
      );

  Widget barra(String rotulo, num valor, num maximo, String texto, [Color? cor]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 90, child: Text(rotulo, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 18,
                  width: maximo == 0 ? 2 : (c.maxWidth * valor / maximo).clamp(2, c.maxWidth).toDouble(),
                  decoration: BoxDecoration(
                    color: cor ?? Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(texto),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (leads == null || vendas == null) return const Center(child: CircularProgressIndicator());
    final ls = leads!.where((l) => dentro(l['data_atendimento'])).toList();
    final vs = vendas!.where((v) => dentro(v['data_fechamento'])).toList();
    final enc = ls.where((l) => l['encaminhado_em'] != null).length;
    final total = vs.fold<num>(0, (a, v) => a + (v['valor_comissao'] as num));
    final conversao = enc == 0 ? 0 : vs.length * 100 / enc;

    final origens = <String, int>{};
    for (final l in ls) {
      final o = (l['origem'] ?? '').toString().trim();
      final k = o.isEmpty ? 'Sem origem' : o;
      origens[k] = (origens[k] ?? 0) + 1;
    }
    final porOrigem = origens.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    const nomes = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final hoje = DateTime.now();
    final meses = [for (var i = 5; i >= 0; i--) DateTime(hoje.year, hoje.month - i)];
    final porMes = [
      for (final m in meses)
        vendas!
            .where((v) => data(v['data_fechamento']).year == m.year && data(v['data_fechamento']).month == m.month)
            .fold<num>(0, (a, v) => a + (v['valor_comissao'] as num)),
    ];
    final maiorMes = porMes.fold<num>(0, (a, b) => a > b ? a : b);
    final titulo = Theme.of(context).textTheme.titleMedium;

    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'mes', label: Text('Este mês')),
            ButtonSegment(value: '30d', label: Text('30 dias')),
            ButtonSegment(value: 'tudo', label: Text('Tudo')),
          ],
          selected: {periodo},
          onSelectionChanged: (s) => setState(() => periodo = s.first),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          kpi('Leads atendidos', '${ls.length}', azul, Icons.people),
          kpi('Encaminhados', '$enc', laranja, Icons.send),
          kpi('Vendas fechadas', '${vs.length}', verde, Icons.check_circle),
          kpi('Conversão', '${conversao.toStringAsFixed(0)}%', roxo, Icons.trending_up),
          kpi('Comissões', brl(total), petroleo, Icons.payments),
        ]),
        const SizedBox(height: 20),
        Text('Leads por origem', style: titulo),
        const SizedBox(height: 4),
        if (porOrigem.isEmpty) const Text('Sem leads no período.'),
        for (final e in porOrigem.take(8))
          barra(e.key, e.value, porOrigem.first.value, '${e.value}'),
        const SizedBox(height: 20),
        Text('Comissões nos últimos 6 meses', style: titulo),
        const SizedBox(height: 4),
        for (var i = 0; i < meses.length; i++)
          barra('${nomes[meses[i].month - 1]}/${meses[i].year % 100}', porMes[i], maiorMes, brl(porMes[i]), verde),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Lembretes
// Notificação às 9h do dia do "próximo retorno" de cada lead em aberto.
class Lembretes {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ok = false;

  static Future<void> iniciar() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
      await _p.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _p
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ok = true;
    } catch (_) {}
  }

  static Future<void> sincronizar(List<Map<String, dynamic>> leads) async {
    if (!_ok) return;
    try {
      await _p.cancelAll();
      final agora = tz.TZDateTime.now(tz.local);
      for (final l in leads) {
        final dia = l['proximo_retorno'];
        if (dia == null || l['status'] == 'fechado' || l['status'] == 'perdido') continue;
        final d = DateTime.parse(dia.toString());
        final quando = tz.TZDateTime(tz.local, d.year, d.month, d.day, 9);
        if (quando.isBefore(agora)) continue;
        await _p.zonedSchedule(
          (l['id'] as String).hashCode & 0x7fffffff,
          'Hora de cobrar retorno',
          '${l['nome']}: veja com o gerente como está o atendimento.',
          quando,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'retornos',
              'Retornos de leads',
              channelDescription: 'Lembretes para cobrar o retorno do gerente',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {}
  }
}
