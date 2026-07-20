/* Windows Resource Auditor - Dashboard renderer (ES2022 nativo, sem frameworks) | Desenvolvido por Edsilas */
'use strict';

(() => {
  const DATA = readData();

  function readData() {
    try {
      const raw = document.getElementById('wra-data')?.textContent ?? '{}';
      return JSON.parse(raw);
    } catch (e) {
      return { meta: {}, modules: {} };
    }
  }

  // ---------------------------------------------------------------- helpers
  const el = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null) continue;
      if (k === 'class') node.className = v;
      else if (k === 'html') node.innerHTML = v;
      else if (k === 'text') node.textContent = v;
      else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
      else if (k === 'style') node.setAttribute('style', v);
      else node.setAttribute(k, v);
    }
    for (const c of [].concat(children)) {
      if (c == null) continue;
      node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return node;
  };

  const get = (obj, path, dflt = null) => {
    let n = obj;
    for (const seg of path.split('.')) {
      if (n == null) return dflt;
      n = n[seg];
    }
    return n ?? dflt;
  };

  const num = (v) => (typeof v === 'number' ? v : (v == null ? null : Number(v)));
  const fmtNum = (v, d = 0) => (v == null || Number.isNaN(Number(v)) ? '-' : Number(v).toFixed(d).replace(/\.0+$/, ''));
  const pad2 = (n) => String(n).padStart(2, '0');
  // Conversão central de datas: aceita ISO 8601, "yyyy-MM-dd HH:…" e o formato
  // legado "/Date(ms)/" do ConvertTo-Json do Windows PowerShell 5.1 (presente
  // em relatórios já gerados). Retorna Date válido ou null.
  const parseDate = (v) => {
    if (v == null || v === '') return null;
    if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
    if (typeof v === 'string') {
      const legacy = /^\/Date\((-?\d+)\)\/$/.exec(v.trim());
      if (legacy) { const d = new Date(Number(legacy[1])); return Number.isNaN(d.getTime()) ? null : d; }
      let s = v;
      if (/^\d{4}-\d{2}-\d{2} \d{2}:/.test(s)) s = s.replace(' ', 'T');
      const d = new Date(s);
      return Number.isNaN(d.getTime()) ? null : d;
    }
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  };
  // Exibição de data/hora no padrão brasileiro (dd/MM/yyyy HH:mm:ss), consistente
  // em qualquer navegador. A ordenação usa o valor bruto (Date), não este texto.
  const fmtTime = (v) => {
    if (!v) return '-';
    const dt = parseDate(v);
    if (!dt) return String(v);
    return `${pad2(dt.getDate())}/${pad2(dt.getMonth() + 1)}/${dt.getFullYear()} ${pad2(dt.getHours())}:${pad2(dt.getMinutes())}:${pad2(dt.getSeconds())}`;
  };
  // Exibição de data (sem hora) no padrão brasileiro (dd/MM/yyyy). Para valores
  // "yyyy-MM-dd" usa conversão textual, evitando deslocamento de fuso horário.
  const fmtDate = (v) => {
    if (!v) return '-';
    const s = String(v);
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s.slice(0, 10)) && /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
    if (m && !/^\/Date\(/.test(s)) return `${m[3]}/${m[2]}/${m[1]}`;
    const dt = parseDate(s);
    return !dt ? s : `${pad2(dt.getDate())}/${pad2(dt.getMonth() + 1)}/${dt.getFullYear()}`;
  };

  const sevClass = (s) => (s ? String(s).toLowerCase() : '');
  // Traducao apenas de EXIBICAO para indicadores/status vindos da camada de dados.
  // Valores desconhecidos passam inalterados (sem impacto na logica nem nos dados).
  const tLabel = (x) => {
    if (x == null || x === '') return x;
    const map = {
      Critical: 'Crítica', High: 'Alta', Medium: 'Média', Low: 'Baixa',
      Info: 'Info', Informational: 'Informativo', Information: 'Informação',
      Error: 'Erro', Warning: 'Aviso', Verbose: 'Detalhado',
      Pass: 'Aprovado', Fail: 'Reprovado', Warn: 'Atenção', Fixed: 'Corrigido',
      Enabled: 'Habilitado', Disabled: 'Desabilitado', On: 'Ligado', Off: 'Desligado',
      Running: 'Em execução', Stopped: 'Parado', Paused: 'Pausado',
      Valid: 'Válida', Invalid: 'Inválida', Signed: 'Assinado', Unsigned: 'Não assinado',
      Licensed: 'Ativado', Unlicensed: 'Não ativado', NotActivated: 'Não ativado',
      Healthy: 'Saudável', Attention: 'Atenção', Degraded: 'Degradado',
      Unknown: 'Desconhecido', None: 'Nenhum', Yes: 'Sim', No: 'Não'
    };
    return map[x] ?? x;
  };
  const pill = (label, sev) => el('span', { class: `wra-pill ${sevClass(sev)}`, text: (label == null ? '-' : tLabel(label)) });

  // Mapeia o Status do Get-AuthenticodeSignature para indicador claro em pt-BR.
  // sev: ok=sucesso, critical/high=falha, medium/info=indisponivel/nao aplicavel.
  const sigStatusInfo = (s) => {
    if (s == null || s === '') return { label: 'Não verificada', sev: 'medium' };
    const map = {
      Valid: { label: 'Válida', sev: 'ok' },
      NotSigned: { label: 'Não assinada', sev: 'medium' },
      HashMismatch: { label: 'Hash divergente', sev: 'critical' },
      NotTrusted: { label: 'Não confiável', sev: 'high' },
      UnknownError: { label: 'Não verificada', sev: 'medium' },
      NotSupportedFileFormat: { label: 'Não aplicável', sev: 'unknown' },
      Incompatible: { label: 'Não aplicável', sev: 'unknown' },
      FileNotFound: { label: 'Indisponível', sev: 'unknown' }
    };
    return map[s] ?? { label: String(s), sev: 'high' };
  };
  // Exibicao do SHA-256: hash completo na celula (sem corte), pronto para copia.
  const shaDisplay = (h) => {
    if (h == null || h === '') return { text: '—', title: 'Hash não disponível' };
    if (h === 'SKIPPED_TOO_LARGE') return { text: 'não calculado', title: 'Arquivo acima do limite de tamanho configurado' };
    // Hash exibido por completo (sem truncamento), permitindo copia integral.
    const full = String(h);
    return { text: full, title: full };
  };

  // Cor semântica de uma verificação de segurança a partir do Status.
  // Enabled/Running/Valid -> ok (verde); Unknown/N-A -> neutro (nunca verde);
  // estados negativos seguem a severidade (nunca verdes, mesmo com severidade baixa).
  const checkSev = (c) => {
    const st = String((c && c.Status) || '').toLowerCase();
    if (['enabled', 'running', 'pass', 'on', 'valid', 'ok', 'protected', 'active'].includes(st)) return 'ok';
    if (st === '' || st === 'unknown') return 'unknown';
    if (['notpresent', 'notsupported', 'notapplicable', 'na', 'n/a'].includes(st)) return 'unknown';
    const s = sevClass(c && c.Severity);
    return s === 'low' ? 'medium' : (s || 'medium');
  };

  // ---------------------------------------------------------------- sections
  const sections = [];
  const addSection = (id, title, build) => {
    const body = el('div');
    try {
      const ok = build(body);
      if (ok === false) return;
    } catch (e) {
      body.appendChild(el('div', { class: 'wra-empty', text: 'Falha ao renderizar esta seção.' }));
    }
    const sec = el('section', { class: 'wra-section', id }, [
      el('p', { class: 'wra-eyebrow', text: title.toUpperCase() }),
      el('h2', { class: 'wra-h2', text: title }),
      body
    ]);
    sections.push({ id, title, node: sec });
  };

  const panel = (title, bodyNode, tools = []) =>
    el('div', { class: 'wra-panel' }, [
      el('div', { class: 'wra-panel-head' }, [
        el('div', { class: 'wra-panel-title', text: title }),
        el('div', { class: 'wra-panel-tools' }, tools)
      ]),
      bodyNode
    ]);

  const csvButton = (getTable, name) =>
    el('button', {
      class: 'wra-mini-btn', type: 'button', text: 'CSV',
      onclick: () => exportTableCsv(getTable(), name)
    });

  // ---------------------------------------------------------------- filtros
  // Sistema de correlacao por filtros dinamicos combinaveis (substitui a busca
  // textual). Dimensoes de baixa cardinalidade viram chips multi-selecao (OR
  // dentro da dimensao); alta cardinalidade vira dropdown. Dimensoes combinam
  // entre si (AND). Tudo aplicado instantaneamente, sem recarregar a pagina.
  const fkey = (k) => 'f' + String(k).replace(/[^A-Za-z0-9]/g, '');

  const distinctValues = (rows, valueFn) => {
    const seen = new Map();
    for (const r of rows) {
      let v = valueFn(r);
      if (v == null || v === '') continue;
      v = String(v);
      seen.set(v, (seen.get(v) ?? 0) + 1);
    }
    return [...seen.entries()].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0])));
  };

  const applyRowFilters = (rows, active, counterEl, total) => {
    let shown = 0;
    for (const tr of rows) {
      let vis = true;
      for (const key of Object.keys(active)) {
        const set = active[key];
        if (!set || set.size === 0) continue;
        if (!set.has(tr.dataset[fkey(key)] ?? '')) { vis = false; break; }
      }
      tr.classList.toggle('wra-row-hidden', !vis);
      if (vis) shown++;
    }
    if (counterEl) counterEl.textContent = `Mostrando ${shown} de ${total}`;
  };

  // dims: [{ key, label, values:[[val,count],...], fmt?(val)->text }]
  // Retorna um controlador { el, setActive(key,[values]), clearAll() } para que
  // os indicadores do painel possam aplicar filtros programaticamente.
  const buildFilterBar = (dims, onApply) => {
    const active = {};
    const controls = {};
    for (const d of dims) active[d.key] = new Set();
    const bar = el('div', { class: 'wra-filters' });
    const apply = () => onApply(active);

    for (const d of dims) {
      const fmt = d.fmt ?? tLabel;
      const group = el('div', { class: 'wra-filter-group' });
      group.appendChild(el('span', { class: 'wra-filter-label', text: d.label }));
      if (d.values.length > 12) {
        const sel = el('select', { class: 'wra-select wra-filter-select',
          onchange: (e) => { active[d.key] = e.target.value === '__all__' ? new Set() : new Set([e.target.value]); apply(); }
        }, [el('option', { value: '__all__', text: `Todos (${d.values.length})` }),
            ...d.values.map(([v, c]) => el('option', { value: v, text: `${fmt(v)} (${c})` }))]);
        group.appendChild(sel);
        controls[d.key] = { type: 'select', sel };
      } else {
        const chips = el('div', { class: 'wra-chips' });
        const chipMap = new Map();
        for (const [v, c] of d.values) {
          const chip = el('button', { class: 'wra-chip', type: 'button' }, [
            el('span', { text: fmt(v) }), el('span', { class: 'wra-chip-c', text: String(c) })
          ]);
          chip.addEventListener('click', () => {
            const set = active[d.key];
            if (set.has(v)) { set.delete(v); chip.classList.remove('active'); }
            else { set.add(v); chip.classList.add('active'); }
            apply();
          });
          chips.appendChild(chip);
          chipMap.set(v, chip);
        }
        group.appendChild(chips);
        controls[d.key] = { type: 'chips', chipMap };
      }
      bar.appendChild(group);
    }

    const reflect = () => {
      for (const k of Object.keys(controls)) {
        const ctl = controls[k]; const set = active[k] ?? new Set();
        if (ctl.type === 'chips') ctl.chipMap.forEach((chip, val) => chip.classList.toggle('active', set.has(val)));
        else ctl.sel.value = (set.size === 1) ? [...set][0] : '__all__';
      }
    };
    const clearAll = () => { for (const k of Object.keys(active)) active[k] = new Set(); reflect(); apply(); };
    const setActiveFilter = (key, values) => {
      if (!(key in active)) return false;
      for (const k of Object.keys(active)) active[k] = new Set();
      active[key] = new Set((values || []).map(String));
      reflect(); apply();
      return true;
    };

    const clear = el('button', { class: 'wra-mini-btn wra-filter-clear', type: 'button', text: 'Limpar filtros' });
    clear.addEventListener('click', clearAll);
    bar.appendChild(clear);
    return { el: bar, setActive: setActiveFilter, clearAll };
  };

  // Registro de controladores de filtro por id, para que indicadores do painel
  // possam abrir a lista detalhada correspondente (resumo -> detalhe).
  const filterControllers = {};
  const registerFilter = (id, ctrl) => { if (id) filterControllers[id] = ctrl; };
  const activateFilter = (id, dimKey, value) => {
    const c = filterControllers[id];
    if (!c) return;
    if (c.sectionId && typeof setActive === 'function') setActive(c.sectionId);
    if (dimKey && c.setActive) c.setActive(dimKey, value == null ? [] : [value]);
    else if (c.clearAll) c.clearAll();
    if (c.scrollEl && c.scrollEl.scrollIntoView) c.scrollEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  const navTo = (sectionId) => {
    if (typeof setActive === 'function') setActive(sectionId);
    const node = document.getElementById(sectionId);
    if (node && node.scrollIntoView) node.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  // Ordenacao por coluna (clique no cabecalho). sortDefs[i]: false = nao ordenavel,
  // funcao(row)->valor para chave custom, ou null/undefined = usa o texto da celula.
  const makeSortable = (table, trs, sortDefs) => {
    const thead = table.tHead; const tbody = table.tBodies[0];
    if (!thead || !tbody) return;
    const ths = Array.from(thead.querySelectorAll('th'));
    const cur = { i: -1, dir: 1 };
    ths.forEach((th, i) => {
      const def = sortDefs ? sortDefs[i] : null;
      if (def === false) return;
      th.classList.add('is-sortable');
      th.appendChild(el('span', { class: 'wra-sort-ind' }));
      th.addEventListener('click', () => {
        cur.dir = (cur.i === i) ? -cur.dir : 1; cur.i = i;
        const valOf = (tr) => {
          if (typeof def === 'function') return def(tr.__row);
          return tr.children[i] ? tr.children[i].textContent : '';
        };
        const sorted = [...trs].sort((a, b) => {
          const va = valOf(a), vb = valOf(b);
          const na = Number(va), nb = Number(vb);
          let cmp;
          if (!Number.isNaN(na) && !Number.isNaN(nb) && String(va).trim() !== '' && String(vb).trim() !== '') cmp = na - nb;
          else cmp = String(va ?? '').localeCompare(String(vb ?? ''), 'pt-BR', { numeric: true });
          return cmp * cur.dir;
        });
        for (const tr of sorted) tbody.appendChild(tr);
        ths.forEach((t, j) => {
          const ind = t.querySelector('.wra-sort-ind');
          if (ind) ind.textContent = (j === i) ? (cur.dir > 0 ? ' ▲' : ' ▼') : '';
          t.classList.toggle('sorted', j === i);
        });
      });
    });
  };

  const buildTable = (columns, rows, opts = {}) => {
    const wrap = el('div', { class: 'wra-tablewrap' });
    if (!rows || rows.length === 0) {
      wrap.appendChild(el('div', { class: 'wra-empty', text: opts.empty ?? 'Sem dados.' }));
      if (opts.filterId) registerFilter(opts.filterId, { scrollEl: wrap, sectionId: opts.sectionId });
      return wrap;
    }
    const thead = el('thead', {}, [el('tr', {}, columns.map(c => el('th', { class: c.cls ?? '', text: c.label })))]);
    const tbody = el('tbody');
    const trs = [];
    for (const r of rows) {
      const tr = el('tr', { class: 'wra-row' });
      tr.__row = r;
      if (opts.filters) {
        for (const fdef of opts.filters) {
          const v = fdef.value(r);
          tr.dataset[fkey(fdef.key)] = (v == null ? '' : String(v));
        }
      }
      for (const c of columns) {
        const raw = c.value(r);
        let td;
        if (c.pill) td = el('td', {}, [pill(raw, c.pill(r))]);
        else td = el('td', { class: c.cls ?? '', text: raw == null ? '-' : String(raw) });
        if (c.title) { const tt = c.title(r); if (tt) td.title = tt; }
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
      trs.push(tr);
    }
    const table = el('table', { class: 'wra-table' }, [thead, tbody]);
    let ctrl = { scrollEl: wrap, sectionId: opts.sectionId };
    if (opts.filters && opts.filters.length) {
      const dims = opts.filters
        .map(f => ({ key: f.key, label: f.label, fmt: f.fmt, values: distinctValues(rows, f.value) }))
        .filter(d => d.values.length > 1);
      if (dims.length) {
        const counter = el('div', { class: 'wra-filter-count', text: `Mostrando ${rows.length} de ${rows.length}` });
        const fbar = buildFilterBar(dims, (active) => applyRowFilters(trs, active, counter, rows.length));
        fbar.el.appendChild(counter);
        wrap.appendChild(fbar.el);
        ctrl.setActive = fbar.setActive; ctrl.clearAll = fbar.clearAll;
      }
    }
    if (opts.sortable !== false) makeSortable(table, trs, columns.map(c => c.sortable === false ? false : (c.sortValue ?? null)));
    wrap.appendChild(table);
    registerFilter(opts.filterId, ctrl);
    return wrap;
  };

  // ---------- Itens que Requerem Atenção (visão orientada a ação)
  const attentionRank = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };
  const prioMeta = {
    critical: { label: 'Crítico', sev: 'critical' },
    high: { label: 'Alto', sev: 'high' },
    medium: { label: 'Médio', sev: 'medium' },
    low: { label: 'Baixo', sev: 'low' },
    info: { label: 'Informativo', sev: 'info' }
  };
  const prioFromSeverity = (s) => {
    const k = sevClass(s);
    if (k === 'critical') return 'critical';
    if (k === 'high') return 'high';
    if (k === 'medium') return 'medium';
    if (k === 'info') return 'info';
    return 'low';
  };
  const collectAttention = () => {
    const items = [];
    // Cada item declara: componente, situação, prioridade, impacto e recomendação.
    const add = (prio, component, situation, impact, recommendation, action) =>
      items.push({ prio, component, situation, impact, recommendation, action });

    // 1) Recomendações de segurança (achados priorizados por severidade).
    const sec = get(DATA, 'modules.Security.data');
    for (const r of (get(sec, 'Recommendations', []) ?? [])) {
      add(prioFromSeverity(r.Severity), r.Area ?? 'Segurança', r.Finding ?? 'Recomendação de segurança',
        'Pode afetar a segurança ou a conformidade do sistema.', r.Recommendation ?? '', () => activateFilter('security-rec', null));
    }
    // 2) Licença do Windows (ativação / expiração).
    const lic = get(DATA, 'modules.Inventory.data.Licensing');
    if (lic) {
      const code = lic.StatusCode, days = lic.GraceDaysRemaining;
      if (code === 0 || code === 5) add('critical', 'Licença do Windows', lic.Situation ?? 'Windows não ativado',
        'Sistema não ativado: recursos podem ser limitados e o Windows pode exibir avisos.',
        'Ative o Windows com uma licença válida.', () => navTo('resumo'));
      else if (code === 3) add('high', 'Licença do Windows', 'Necessita reativação',
        'A ativação expirou ou tornou-se inválida.', 'Reative o Windows.', () => navTo('resumo'));
      else if (typeof days === 'number' && days >= 0 && days <= 30) add(days <= 7 ? 'high' : 'medium', 'Licença do Windows',
        lic.Situation ?? `Licença expira em ${days} dia(s)`, 'A licença/ativação expirará em breve.',
        'Renove ou reative a licença antes do vencimento.', () => navTo('resumo'));
    }
    // 3) Eventos do Windows (críticos e de erro nos últimos dias).
    const mon = get(DATA, 'modules.Monitor.data');
    const crit = Number(get(mon, 'Events.Critical', 0)) || 0;
    const errs = Number(get(mon, 'Events.Error', 0)) || 0;
    if (crit > 0) add('high', 'Eventos', `${crit} evento(s) crítico(s) registrado(s)`,
      'Podem indicar falhas de hardware, driver ou sistema.', 'Analise os eventos críticos para identificar a causa.', () => activateFilter('events', 'Nivel', 'Critico'));
    if (errs > 0) add('medium', 'Eventos', `${errs} evento(s) de erro registrado(s)`,
      'Podem indicar componentes com mau funcionamento.', 'Verifique os eventos de erro recentes.', () => activateFilter('events', 'Nivel', 'Erro'));
    // 4) Serviços automáticos parados (excluindo início atrasado com saída limpa).
    const auto = (get(mon, 'Services.AutoStartNotRunning', []) ?? []).filter(s => !(s.Delayed === true && s.CleanExit === true));
    if (auto.length > 0) add('high', 'Serviços', `${auto.length} serviço(s) automático(s) parado(s)`,
      'Funções que deveriam estar ativas podem não estar operando.', 'Verifique e inicie os serviços necessários.', () => navTo('services'));
    // 5) Processos sinalizados na correlação.
    const flagged = get(DATA, 'modules.ProcessAnalyzer.data.Correlation.Flagged', []) ?? [];
    if (flagged.length > 0) add('medium', 'Processos', `${flagged.length} processo(s) sinalizado(s)`,
      'Processos incomuns podem indicar risco ou má configuração.', 'Verifique os processos sinalizados.', () => navTo('processes'));

    items.sort((a, b) => (attentionRank[a.prio] - attentionRank[b.prio]) || String(a.component).localeCompare(String(b.component), 'pt-BR'));
    return items;
  };

  addSection('atencao', 'Itens que Requerem Atenção', (body) => {
    const items = collectAttention();
    if (!items.length) {
      body.appendChild(el('div', { class: 'wra-allclear' }, [
        el('div', { class: 'wra-allclear-badge', text: '✓' }),
        el('div', {}, [
          el('div', { class: 'wra-allclear-title', text: 'Nenhum item requer atenção no momento.' }),
          el('div', { class: 'wra-allclear-sub', text: 'Não foram identificados componentes que exijam análise, correção ou intervenção nesta auditoria.' })
        ])
      ]));
      return;
    }
    // Resumo por prioridade (identificação rápida do que exige ação).
    const counts = { critical: 0, high: 0, medium: 0, low: 0, info: 0 };
    for (const it of items) counts[it.prio] = (counts[it.prio] || 0) + 1;
    const summary = el('div', { class: 'wra-grid wra-prio-grid' });
    for (const key of ['critical', 'high', 'medium', 'low', 'info']) {
      if (!counts[key]) continue;
      const m = prioMeta[key];
      const card = el('div', { class: 'wra-card is-clickable' }, [
        el('div', { class: 'wra-statusrow', style: 'justify-content:space-between' }, [
          el('div', { class: 'k', text: m.label }), el('span', { class: `wra-dot ${m.sev}` })]),
        el('div', { class: 'v', text: String(counts[key]) })
      ]);
      card.setAttribute('role', 'button');
      card.title = 'Ver itens desta prioridade';
      card.addEventListener('click', () => { const t = document.getElementById('wra-atencao-list'); if (t) t.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
      summary.appendChild(card);
    }
    body.appendChild(summary);

    // Lista priorizada de itens acionáveis (componente, situação, impacto, recomendação).
    const list = el('div', { class: 'wra-attn-list', id: 'wra-atencao-list' });
    for (const it of items) {
      const m = prioMeta[it.prio];
      const row = el('div', { class: 'wra-attn' + (it.action ? ' is-clickable' : '') }, [
        el('div', { class: 'wra-attn-prio' }, [pill(m.label, m.sev)]),
        el('div', { class: 'wra-attn-body' }, [
          el('div', { class: 'wra-attn-comp', text: it.component }),
          el('div', { class: 'wra-attn-sit', text: it.situation }),
          it.impact ? el('div', { class: 'wra-attn-line' }, [el('span', { class: 'wra-attn-tag', text: 'Impacto: ' }), el('span', { text: it.impact })]) : null,
          it.recommendation ? el('div', { class: 'wra-attn-line' }, [el('span', { class: 'wra-attn-tag', text: 'Recomendação: ' }), el('span', { text: it.recommendation })]) : null
        ])
      ]);
      if (it.action) { row.setAttribute('role', 'button'); row.addEventListener('click', it.action); }
      list.appendChild(row);
    }
    body.appendChild(panel(`Itens priorizados (${items.length})`, list));
  });

  // ---------- Resumo do sistema
  addSection('resumo', 'Resumo do sistema', (body) => {
    // Licença do Microsoft Windows (dados oficiais do sistema).
    const wlic = get(DATA, 'modules.Inventory.data.Licensing');
    const edition = get(DATA, 'modules.Inventory.data.OperatingSystem.Caption');
    if (wlic && (wlic.StatusCode != null || wlic.Situation)) {
      const code = wlic.StatusCode, days = wlic.GraceDaysRemaining;
      let licSev = 'info';
      if (code === 1 && days == null) licSev = 'ok';
      else if (code === 0 || code === 5) licSev = 'critical';
      else if (code === 3) licSev = 'high';
      else if (typeof days === 'number') licSev = days <= 7 ? 'high' : (days <= 30 ? 'medium' : 'ok');
      const rows = [
        ['Situação', wlic.Situation || tLabel(wlic.WindowsActivation) || 'Desconhecido'],
        ['Status de ativação', wlic.Status || tLabel(wlic.WindowsActivation)],
        ['Edição do Windows', edition || 'n/d'],
        ['Tipo de licença', wlic.Type && wlic.Type !== 'Desconhecido' ? wlic.Type : 'Não identificado'],
        ['Canal', wlic.Channel || 'n/d'],
        ['Expiração', wlic.ExpiryDate ? `${fmtDate(wlic.ExpiryDate)}${typeof days === 'number' ? ` (${days} dia(s) restante(s))` : ''}` : 'Não aplicável']
      ];
      const licBox = el('div', { class: 'wra-license' }, [
        el('div', { class: 'wra-license-head' }, [
          el('span', { class: `wra-dot ${licSev}` }),
          el('span', { class: 'wra-license-title', text: 'Licença do Windows' })
        ]),
        el('div', { class: 'wra-license-grid' }, rows.map(([k, v]) =>
          el('div', { class: 'wra-license-item' }, [
            el('div', { class: 'wra-license-k', text: k }),
            el('div', { class: 'wra-license-v', text: String(v) })
          ])))
      ]);
      body.appendChild(licBox);
    }

    // Executive summary cards
    const mon = get(DATA, 'modules.Monitor.data');
    const inv = get(DATA, 'modules.Inventory.data');
    const sec = get(DATA, 'modules.Security.data');
    const facts = [];
    // Valor com unidade apenas quando o dado existe (evita "- %"/"- GB").
    const withUnit = (v, d, unit) => (v == null || Number.isNaN(Number(v)) ? 'n/d' : `${fmtNum(v, d)} ${unit}`);
    if (inv) {
      facts.push(['Sistema', get(inv, 'OperatingSystem.Caption', '-'), get(inv, 'Summary.Model', '')]);
      facts.push(['Memória total', withUnit(get(inv, 'Summary.TotalRamGB'), 1, 'GB'), '']);
      facts.push(['Ativação', tLabel(get(inv, 'Summary.Activation', '-')), '']);
    }
    if (mon) {
      facts.push(['CPU média', withUnit(get(mon, 'Cpu.AveragePercent'), 1, '%'), get(mon, 'Cpu.Status', '')]);
      facts.push(['Memória em uso', withUnit(get(mon, 'Memory.UsedPercent'), 1, '%'), get(mon, 'Memory.Status', '')]);
      facts.push(['Eventos críticos', String(get(mon, 'Events.Critical', 0)), '', () => activateFilter('events', 'Nivel', 'Critico')]);
    }
    if (sec) {
      facts.push(['Recomendações', String((get(sec, 'Recommendations', []) ?? []).length), '', () => activateFilter('security-rec', null)]);
    }
    const cardGrid = el('div', { class: 'wra-grid' });
    for (const [k, v, s, onClick] of facts) {
      // Valores textuais longos (ex.: nome do SO) usam tipografia proporcional
      // menor, evitando que um único cartão estique a fileira inteira.
      const isLongText = String(v ?? '').length > 14 && Number.isNaN(Number(String(v).replace(',', '.').replace(/[%\s]/g, '')));
      const card = el('div', { class: 'wra-card' + (onClick ? ' is-clickable' : '') + (isLongText ? ' has-vsm' : ''), }, [
        el('div', { class: 'k', text: k }),
        el('div', { class: 'v' + (isLongText ? ' v-sm' : ''), text: v }),
        s ? el('div', { class: 'wra-statusrow' }, [el('span', { class: `wra-dot ${sevClass(s)}` }), el('span', { class: 's', text: s })]) : null
      ]);
      if (onClick) { card.setAttribute('role', 'button'); card.addEventListener('click', onClick); }
      cardGrid.appendChild(card);
    }
    body.appendChild(cardGrid);

    // Module status
    const sectionFor = { Inventory: 'inventory', ProcessAnalyzer: 'processes', Network: 'network', Security: 'security', Monitor: 'events' };
    const modGrid = el('div', { class: 'wra-grid', style: 'margin-top:14px' });
    for (const [name, m] of Object.entries(DATA.modules ?? {})) {
      const ok = !!m.success;
      const w = (m.warnings ?? []).length, e = (m.errors ?? []).length;
      const target = sectionFor[name];
      const card = el('div', { class: 'wra-card' + (target ? ' is-clickable' : '') }, [
        el('div', { class: 'k', text: name }),
        el('div', { class: 'wra-statusrow' }, [
          el('span', { class: `wra-dot ${ok ? 'ok' : 'critical'}` }),
          el('span', { class: 's', text: ok ? 'Concluído' : 'Com falha' })
        ]),
        el('div', { class: 's', text: `${fmtNum(m.durationMs, 0)} ms - ${w} avisos, ${e} erros` })
      ]);
      if (target) { card.setAttribute('role', 'button'); card.addEventListener('click', () => navTo(target)); }
      modGrid.appendChild(card);
    }
    body.appendChild(el('p', { class: 'wra-eyebrow', style: 'margin-top:24px', text: 'MÓDULOS' }));
    body.appendChild(modGrid);
  });

  // ---------- Inventory
  const inv = get(DATA, 'modules.Inventory.data');
  if (inv) {
    addSection('inventory', 'Inventário', (body) => {
      const factPanel = (title, pairs) => {
        const wrap = el('div', { class: 'wra-facts' });
        for (const [k, v] of pairs) wrap.appendChild(el('div', { class: 'wra-fact' }, [el('span', { class: 'fk', text: k }), el('span', { class: 'fv', text: v == null ? '-' : String(v) })]));
        return panel(title, el('div', { style: 'padding:14px 15px' }, [wrap]));
      };
      const hw = get(inv, 'Hardware') ?? {};
      const os = get(inv, 'OperatingSystem') ?? {};
      const fw = get(inv, 'Firmware') ?? {};
      const cpu0 = (get(hw, 'Cpu', []) ?? [])[0] ?? {};
      body.appendChild(factPanel('Sistema', [
        ['Fabricante', hw.Manufacturer], ['Modelo', hw.Model], ['Tipo', hw.SystemType],
        ['Serial', hw.SerialNumber], ['Domínio', hw.Domain],
        ['SO', os.Caption], ['Versão', os.Version], ['Build', os.Build], ['Arquitetura', os.Architecture],
        ['Instalado em', fmtTime(os.InstallDate)], ['Último boot', fmtTime(os.LastBootUpTime)],
        ['BIOS', fw.BiosVersion], ['Firmware', fw.FirmwareType],
        ['CPU', cpu0.Name], ['Núcleos', cpu0.Cores], ['Lógicos', cpu0.LogicalProcs],
        ['RAM total', `${fmtNum(hw.TotalRamGB, 1)} GB`]
      ]));

      const vols = get(inv, 'Storage.Volumes', []) ?? [];
      body.appendChild(panel('Volumes', buildTable([
        { label: 'Unidade', value: r => r.Drive }, { label: 'Rótulo', value: r => r.Label },
        { label: 'FS', value: r => r.FileSystem },
        { label: 'Tamanho GB', cls: 'num', value: r => fmtNum(r.SizeGB, 1) },
        { label: 'Livre GB', cls: 'num', value: r => fmtNum(r.FreeGB, 1) },
        { label: 'Uso %', cls: 'num', value: r => fmtNum(r.UsedPercent, 1) }
      ], vols)));

      const progs = get(inv, 'Programs', []) ?? [];
      const tbl = buildTable([
        { label: 'Programa', value: r => r.Name }, { label: 'Versão', cls: 'mono', value: r => r.Version },
        { label: 'Fabricante', value: r => r.Publisher }
      ], progs, { empty: 'Nenhum programa listado.', filters: [{ key: 'Fabricante', label: 'Fabricante', value: r => r.Publisher }] });
      body.appendChild(panel(`Programas instalados (${progs.length})`, tbl, [csvButton(() => tbl.querySelector('table'), 'programas')]));
    });
  }

  // ---------- Processes
  const proc = get(DATA, 'modules.ProcessAnalyzer.data');
  if (proc) {
    addSection('processes', 'Processos', (body) => {
      const list = get(proc, 'Processes', []) ?? [];
      const top = [...list].sort((a, b) => (b.WorkingSetMB ?? 0) - (a.WorkingSetMB ?? 0)).slice(0, 10);
      const maxMem = Math.max(1, ...top.map(p => p.WorkingSetMB ?? 0));
      const bars = el('div', { class: 'wra-bars', style: 'padding:14px 15px' });
      for (const p of top) {
        bars.appendChild(el('div', { class: 'wra-bar-row' }, [
          el('div', { class: 'wra-bar-name', text: p.Name ?? '-' }),
          el('div', { class: 'wra-bar-track' }, [el('div', { class: 'wra-bar-fill', style: `width:${((p.WorkingSetMB ?? 0) / maxMem * 100).toFixed(1)}%` })]),
          el('div', { class: 'wra-bar-val', text: `${fmtNum(p.WorkingSetMB, 0)} MB` })
        ]));
      }
      body.appendChild(panel('Principais processos por memória', bars));

      const psum = get(proc, 'Summary', {}) ?? {};
      body.appendChild(el('div', { class: 'wra-grid' }, [
        el('div', { class: 'wra-card' }, [
          el('div', { class: 'wra-statusrow', style: 'justify-content:space-between' }, [el('div', { class: 'k', text: 'Assinatura válida' }), el('span', { class: 'wra-dot ok' })]),
          el('div', { class: 'v', text: String(psum.Signed ?? 0) })
        ]),
        el('div', { class: 'wra-card' }, [
          el('div', { class: 'wra-statusrow', style: 'justify-content:space-between' }, [el('div', { class: 'k', text: 'Sem assinatura válida' }), el('span', { class: 'wra-dot high' })]),
          el('div', { class: 'v', text: String(psum.Unsigned ?? 0) })
        ]),
        el('div', { class: 'wra-card' }, [
          el('div', { class: 'wra-statusrow', style: 'justify-content:space-between' }, [el('div', { class: 'k', text: 'Não verificada' }), el('span', { class: 'wra-dot medium' })]),
          el('div', { class: 'v', text: String(psum.SignatureUnknown ?? 0) })
        ]),
        ((c) => { c.setAttribute('role', 'button'); c.title = 'Ver todos os processos'; c.addEventListener('click', () => activateFilter('processes', null)); return c; })(el('div', { class: 'wra-card is-clickable' }, [el('div', { class: 'k', text: 'Processos analisados' }), el('div', { class: 'v', text: String(psum.Analyzed ?? list.length) })]))
      ]));

      const tbl = buildTable([
        { label: 'Nome', value: r => r.Name }, { label: 'PID', cls: 'num', value: r => r.ProcessId },
        { label: 'PPID', cls: 'num', value: r => r.ParentProcessId }, { label: 'Usuário', value: r => r.User },
        { label: 'WS MB', cls: 'num', value: r => fmtNum(r.WorkingSetMB, 1) },
        { label: 'Threads', cls: 'num', value: r => r.ThreadCount }, { label: 'Handles', cls: 'num', value: r => r.HandleCount },
        { label: 'Assinatura', value: r => sigStatusInfo(r.SignatureStatus).label, pill: r => sigStatusInfo(r.SignatureStatus).sev, title: r => (r.Signer ? ('Assinante: ' + r.Signer) : (r.SignatureStatus ? ('Status: ' + r.SignatureStatus) : '')) },
        { label: 'SHA-256', cls: 'mono wra-sha', value: r => shaDisplay(r.Sha256).text, title: r => shaDisplay(r.Sha256).title }
      ], list, { empty: 'Nenhum processo.', filterId: 'processes', sectionId: 'processes', filters: [
        { key: 'Assinatura', label: 'Assinatura', value: r => r.SignatureStatus, fmt: v => sigStatusInfo(v).label },
        { key: 'Usuario', label: 'Usuário', value: r => r.User }
      ] });
      body.appendChild(panel(`Processos (${list.length})`, tbl, [csvButton(() => tbl.querySelector('table'), 'processos')]));

      const flagged = get(proc, 'Correlation.Flagged', []) ?? [];
      if (flagged.length) {
        const ft = buildTable([
          { label: 'Nome', value: r => r.Name }, { label: 'PID', cls: 'num', value: r => r.ProcessId },
          { label: 'Flags', value: r => (r.Flags ?? []).join(', ') }
        ], flagged);
        body.appendChild(panel(`Processos sinalizados (${flagged.length})`, ft));
      }
    });
  }

  // ---------- Network
  const net = get(DATA, 'modules.Network.data');
  if (net) {
    addSection('network', 'Rede', (body) => {
      const ifaces = get(net, 'Interfaces', []) ?? [];
      body.appendChild(panel('Interfaces', buildTable([
        { label: 'Nome', value: r => (r.Name && String(r.Name).trim()) || r.Description || '—' }, { label: 'IPv4', cls: 'mono', value: r => (r.IPv4 ?? []).join(', ') },
        { label: 'Gateway', cls: 'mono', value: r => (r.Gateway ?? []).join(', ') },
        { label: 'DNS', cls: 'mono', value: r => (r.DnsServers ?? []).join(', ') },
        { label: 'DHCP', value: r => (r.DhcpEnabled ? 'Sim' : 'Não') },
        { label: 'Mbps', cls: 'num', value: r => r.SpeedMbps }, { label: 'MTU', cls: 'num', value: r => r.Mtu }
      ], ifaces)));

      const conns = get(net, 'Connections', []) ?? [];
      const ct = buildTable([
        { label: 'Proto', value: r => r.Protocol }, { label: 'Local', cls: 'mono', value: r => `${r.LocalAddress}:${r.LocalPort}` },
        { label: 'Remoto', cls: 'mono', value: r => (r.RemoteAddress ? `${r.RemoteAddress}:${r.RemotePort}` : '-') },
        { label: 'Estado', value: r => r.State }, { label: 'PID', cls: 'num', value: r => r.ProcessId },
        { label: 'Processo', value: r => r.ProcessName }, { label: 'Serviços', value: r => (r.Services ?? []).join(', ') },
        { label: 'Interface', value: r => r.Interface }
      ], conns, { empty: 'Nenhuma conexão.', filters: [
        { key: 'Proto', label: 'Proto', value: r => r.Protocol },
        { key: 'Estado', label: 'Estado', value: r => r.State },
        { key: 'Interface', label: 'Interface', value: r => r.Interface }
      ] });
      body.appendChild(panel(`Conexões (${conns.length})`, ct, [csvButton(() => ct.querySelector('table'), 'conexoes')]));

      const fw = get(net, 'FirewallProfiles', []) ?? [];
      const shares = get(net, 'Shares', []) ?? [];
      const summaryFacts = el('div', { class: 'wra-facts' });
      summaryFacts.appendChild(el('div', { class: 'wra-fact' }, [el('span', { class: 'fk', text: 'Proxy habilitado' }), el('span', { class: 'fv', text: get(net, 'Proxy.Enabled') ? 'Sim' : 'Não' })]));
      for (const f of fw) summaryFacts.appendChild(el('div', { class: 'wra-fact' }, [el('span', { class: 'fk', text: `Firewall ${f.Name}` }), el('span', { class: 'fv', text: String(f.Enabled) })]));
      summaryFacts.appendChild(el('div', { class: 'wra-fact' }, [el('span', { class: 'fk', text: 'Compartilhamentos' }), el('span', { class: 'fv', text: String(shares.length) })]));
      body.appendChild(panel('Firewall e compartilhamentos', el('div', { style: 'padding:14px 15px' }, [summaryFacts])));
    });
  }

  // ---------- Security
  const sec = get(DATA, 'modules.Security.data');
  if (sec) {
    addSection('security', 'Segurança', (body) => {
      const checks = get(sec, 'Checks', []) ?? [];
      const grid = el('div', { class: 'wra-grid' });
      for (const c of checks) {
        grid.appendChild(el('div', { class: 'wra-card' }, [
          el('div', { class: 'k', text: c.Name }),
          el('div', { class: 'wra-statusrow' }, [el('span', { class: `wra-dot ${checkSev(c)}` }), el('span', {}, [pill(c.Status, checkSev(c))])]),
          el('div', { class: 's', text: c.Detail ?? '' })
        ]));
      }
      body.appendChild(grid);

      const recs = get(sec, 'Recommendations', []) ?? [];
      const recBody = el('div', { style: 'padding:6px 15px 12px' });
      const renderRecs = (filter) => {
        recBody.innerHTML = '';
        const filtered = filter && filter !== 'all' ? recs.filter(r => sevClass(r.Severity) === filter) : recs;
        if (!filtered.length) { recBody.appendChild(el('div', { class: 'wra-empty', text: 'Nenhuma recomendação.' })); return; }
        for (const r of filtered) {
          recBody.appendChild(el('div', { class: 'wra-rec' }, [
            el('div', {}, [pill(r.Severity, r.Severity)]),
            el('div', {}, [
              el('div', { class: 'wra-rec-find', text: r.Finding ?? '' }),
              el('div', { class: 'wra-rec-text', text: r.Recommendation ?? '' }),
              el('div', { class: 'wra-rec-area', text: r.Area ?? '' })
            ])
          ]));
        }
      };
      const sevSelect = el('select', { class: 'wra-select', onchange: (e) => renderRecs(e.target.value) }, [
        el('option', { value: 'all', text: 'Todas severidades' }),
        el('option', { value: 'critical', text: 'Crítica' }),
        el('option', { value: 'high', text: 'Alta' }),
        el('option', { value: 'medium', text: 'Média' }),
        el('option', { value: 'low', text: 'Baixa' })
      ]);
      renderRecs('all');
      const recPanel = panel(`Recomendações (${recs.length})`, recBody, [sevSelect]);
      body.appendChild(recPanel);
      registerFilter('security-rec', {
        scrollEl: recPanel, sectionId: 'security',
        setActive: (key, vals) => { const v = (vals && vals[0]) || 'all'; sevSelect.value = v; renderRecs(v); },
        clearAll: () => { sevSelect.value = 'all'; renderRecs('all'); }
      });
    });
  }

  // ---------- Events (analise de 7 dias + correlacao por filtros)
  const eventLevelLabel = (k) => ({ Critico: 'Crítico', Erro: 'Erro', Aviso: 'Aviso', Informacao: 'Informação', Auditoria: 'Auditoria' }[k] ?? k);
  const eventLevelSev = (k) => ({ Critico: 'critical', Erro: 'high', Auditoria: 'high', Aviso: 'medium', Informacao: 'info' }[k] ?? '');

  const renderEventBars = (title, items, keyFn, valFn, onPick) => {
    const max = Math.max(1, ...items.map(valFn));
    const bars = el('div', { class: 'wra-bars', style: 'padding:14px 15px' });
    for (const it of items) {
      const row = el('div', { class: 'wra-bar-row' + (onPick ? ' is-clickable' : '') }, [
        el('div', { class: 'wra-bar-name', text: keyFn(it) }),
        el('div', { class: 'wra-bar-track' }, [el('div', { class: 'wra-bar-fill', style: `width:${(valFn(it) / max * 100).toFixed(1)}%` })]),
        el('div', { class: 'wra-bar-val', text: String(valFn(it)) })
      ]);
      if (onPick) { row.setAttribute('role', 'button'); row.addEventListener('click', () => onPick(keyFn(it))); }
      bars.appendChild(row);
    }
    return panel(title, bars);
  };

  const renderEventAnalysis = (body, ea) => {
    // Indicadores resumidos por severidade + totais. Cada um abre a lista detalhada.
    const grid = el('div', { class: 'wra-grid' });
    for (const lv of (ea.ByLevel ?? [])) {
      const card = el('div', { class: 'wra-card is-clickable' }, [
        el('div', { class: 'wra-statusrow', style: 'justify-content:space-between' }, [
          el('div', { class: 'k', text: eventLevelLabel(lv.Key) }),
          el('span', { class: `wra-dot ${eventLevelSev(lv.Key)}` })
        ]),
        el('div', { class: 'v', text: String(lv.Count) })
      ]);
      card.setAttribute('role', 'button');
      card.title = 'Ver eventos: ' + eventLevelLabel(lv.Key);
      card.addEventListener('click', () => activateFilter('events', 'Nivel', lv.Key));
      grid.appendChild(card);
    }
    const totalCard = (k, v, onClick) => {
      const card = el('div', { class: 'wra-card' + (onClick ? ' is-clickable' : '') }, [el('div', { class: 'k', text: k }), el('div', { class: 'v', text: String(v) })]);
      if (onClick) { card.setAttribute('role', 'button'); card.title = 'Ver todos os eventos'; card.addEventListener('click', onClick); }
      return card;
    };
    grid.appendChild(totalCard('Total coletado', ea.TotalCollected ?? 0, () => activateFilter('events', null)));
    grid.appendChild(totalCard('Grupos', ea.GroupCount ?? 0, () => activateFilter('events', null)));
    grid.appendChild(totalCard('Período (dias)', ea.LookbackDays ?? 7));
    body.appendChild(grid);

    const byDay = ea.ByDay ?? [];
    if (byDay.length) body.appendChild(renderEventBars('Eventos por dia', byDay, d => fmtDate(d.Date), d => d.Count ?? 0));
    const byProv = ea.ByProvider ?? [];
    if (byProv.length) body.appendChild(renderEventBars('Principais origens', byProv, p => p.Key, p => p.Count ?? 0, (k) => activateFilter('events', 'Origem', k)));
    const byLog = ea.ByLog ?? [];
    if (byLog.length) body.appendChild(renderEventBars('Eventos por log', byLog, l => l.Key, l => l.Count ?? 0, (k) => activateFilter('events', 'Log', k)));

    const groups = ea.Groups ?? [];
    if (!groups.length) { body.appendChild(el('div', { class: 'wra-empty', text: 'Nenhum evento relevante no período.' })); return; }

    // Tabela agrupada (duplicados/semelhantes reduzidos a grupos) com destaque
    // automatico de criticos e recorrentes.
    const cols = ['Nível', 'Última ocorrência', 'Qtd', 'Log', 'ID', 'Origem', 'Categoria', 'Descrição'];
    const thead = el('thead', {}, [el('tr', {}, cols.map((c, i) => el('th', { class: (i === 2 || i === 4) ? 'num' : '', text: c })))]);
    const tbody = el('tbody');
    const trs = [];
    for (const g of groups) {
      const klass = ['wra-row'];
      if (g.Critical) klass.push('is-critical');
      if (g.Recurring) klass.push('is-recurring');
      const tr = el('tr', { class: klass.join(' ') });
      tr.__row = g;
      tr.dataset[fkey('Nivel')] = g.Level ?? '';
      tr.dataset[fkey('Log')] = g.Log ?? '';
      tr.dataset[fkey('Origem')] = g.Provider ?? '';
      tr.dataset[fkey('Categoria')] = g.Category ?? '';
      const qtd = el('td', { class: 'num' }, [el('span', { text: String(g.Count ?? 1) })]);
      if (g.Recurring) qtd.appendChild(el('span', { class: 'wra-badge', text: 'recorrente' }));
      tr.appendChild(el('td', {}, [pill(eventLevelLabel(g.Level), eventLevelSev(g.Level))]));
      tr.appendChild(el('td', { text: fmtTime(g.LastSeen) }));
      tr.appendChild(qtd);
      tr.appendChild(el('td', { text: g.Log ?? '-' }));
      tr.appendChild(el('td', { class: 'num', text: String(g.Id ?? 0) }));
      tr.appendChild(el('td', { text: g.Provider ?? '-' }));
      tr.appendChild(el('td', { text: g.Category ?? '-' }));
      tr.appendChild(el('td', { text: g.Message ?? '' }));
      tbody.appendChild(tr);
      trs.push(tr);
    }
    const table = el('table', { class: 'wra-table' }, [thead, tbody]);

    const dims = [
      { key: 'Nivel', label: 'Nível', fmt: eventLevelLabel, value: g => g.Level },
      { key: 'Log', label: 'Log', value: g => g.Log },
      { key: 'Origem', label: 'Origem', value: g => g.Provider },
      { key: 'Categoria', label: 'Categoria', value: g => g.Category }
    ].map(f => ({ key: f.key, label: f.label, fmt: f.fmt, values: distinctValues(groups, f.value) }))
      .filter(d => d.values.length > 1);

    const wrap = el('div', { class: 'wra-tablewrap' });
    const counter = el('div', { class: 'wra-filter-count', text: `Mostrando ${groups.length} de ${groups.length}` });
    const ctrl = { scrollEl: wrap, sectionId: 'events' };
    if (dims.length) {
      const fbar = buildFilterBar(dims, (active) => applyRowFilters(trs, active, counter, groups.length));
      fbar.el.appendChild(counter);
      wrap.appendChild(fbar.el);
      ctrl.setActive = fbar.setActive; ctrl.clearAll = fbar.clearAll;
    }
    const sevRank = { Critico: 0, Erro: 1, Auditoria: 2, Aviso: 3, Informacao: 4 };
    makeSortable(table, trs, [
      g => sevRank[g.Level] ?? 9,
      g => { const d = parseDate(g.LastSeen); return d ? d.getTime() : 0; },
      g => g.Count ?? 0,
      null,
      g => g.Id ?? 0,
      null, null, null
    ]);
    wrap.appendChild(table);
    registerFilter('events', ctrl);
    body.appendChild(panel(`Eventos agrupados (${groups.length})`, wrap, [csvButton(() => table, 'eventos')]));
  };

  // Fallback: relatorios antigos sem EventAnalysis mantem o timeline original.
  const renderEventsTimeline = (body, eventsItems) => {
    const tl = el('div', { class: 'wra-timeline' });
    const sorted = [...eventsItems].sort((a, b) => ((parseDate(b.TimeCreated)?.getTime()) ?? 0) - ((parseDate(a.TimeCreated)?.getTime()) ?? 0));
    for (const ev of sorted) {
      tl.appendChild(el('div', { class: 'wra-tl-item wra-row' }, [
        el('div', { class: 'wra-tl-time', text: fmtTime(ev.TimeCreated) }),
        el('div', {}, [
          el('div', { class: 'wra-tl-body' }, [pill(ev.Level, ev.Level === 'Critical' ? 'critical' : 'high'), ' ', el('span', { text: ` ${ev.Provider ?? ''} (ID ${ev.Id})` })]),
          el('div', { class: 'wra-tl-meta', text: (ev.Message ?? '').replace(/\s+/g, ' ').slice(0, 200) })
        ])
      ]));
    }
    body.appendChild(panel(`Eventos críticos e de erro (${sorted.length})`, el('div', { style: 'padding:6px 15px' }, [tl])));
  };

  const eventAnalysis = get(DATA, 'modules.Monitor.data.EventAnalysis');
  const eventsItems = get(DATA, 'modules.Monitor.data.Events.Items', []) ?? [];
  if ((eventAnalysis && (eventAnalysis.TotalCollected ?? 0) > 0) || eventsItems.length) {
    addSection('events', 'Eventos', (body) => {
      if (eventAnalysis && (eventAnalysis.TotalCollected ?? 0) > 0) renderEventAnalysis(body, eventAnalysis);
      else renderEventsTimeline(body, eventsItems);
    });
  }

  // ---------- Services
  const services = get(DATA, 'modules.Monitor.data.Services');
  if (services) {
    addSection('services', 'Serviços', (body) => {
      body.appendChild(el('div', { class: 'wra-grid' }, [
        el('div', { class: 'wra-card' }, [el('div', { class: 'k', text: 'Em execução' }), el('div', { class: 'v', text: String(services.Running ?? 0) })]),
        el('div', { class: 'wra-card' }, [el('div', { class: 'k', text: 'Parados' }), el('div', { class: 'v', text: String(services.Stopped ?? 0) })]),
        el('div', { class: 'wra-card' }, [el('div', { class: 'k', text: 'Total' }), el('div', { class: 'v', text: String(services.Total ?? 0) })])
      ]));
      const auto = services.AutoStartNotRunning ?? [];
      // Severidade contextual: "Automático (Atrasado)" que concluiu com saída
      // limpa é comportamento normal (não deve ser sinalizado como problema).
      const startLabel = (r) => (r.Delayed === true ? 'Automático (Atrasado)' : 'Automático');
      const stateSev = (r) => {
        if (r.Delayed === true && r.CleanExit === true) return 'unknown';
        if (r.Delayed === true) return 'medium';
        return 'high';
      };
      const t = buildTable([
        { label: 'Nome', value: r => r.Name },
        { label: 'Exibição', value: r => r.DisplayName },
        { label: 'Início', value: r => startLabel(r) },
        { label: 'Estado', value: r => r.State, pill: r => stateSev(r) }
      ], auto, { empty: 'Nenhum serviço automático parado.', filterId: 'services', sectionId: 'services', filters: [
        { key: 'Início', label: 'Início', value: r => startLabel(r) }
      ] });
      body.appendChild(panel(`Automáticos não em execução (${auto.length})`, t));
    });
  }

  // ---------------------------------------------------------------- mount
  function mount() {
    document.getElementById('wra-version').textContent = 'v' + get(DATA, 'meta.version', '');
    document.getElementById('wra-host').textContent = get(DATA, 'meta.computerName', '');
    const content = document.getElementById('wra-content');
    const navlist = document.getElementById('wra-navlist');
    // Agrupamento do menu (organizacao no estilo da documentacao de referencia).
    // Apenas apresentacao: os links e a navegacao permanecem identicos.
    const navGroups = {
      atencao: 'Visão geral', resumo: 'Visão geral',
      inventory: 'Detalhamento', processes: 'Detalhamento', network: 'Detalhamento',
      security: 'Detalhamento', events: 'Detalhamento', services: 'Detalhamento'
    };
    let lastGroup = null;
    for (const s of sections) {
      content.appendChild(s.node);
      const g = navGroups[s.id] ?? 'Outras seções';
      if (g !== lastGroup) {
        navlist.appendChild(el('div', { class: 'wra-navgroup', text: g }));
        lastGroup = g;
      }
      navlist.appendChild(el('a', { class: 'wra-navlink', href: `#${s.id}`, onclick: () => setActive(s.id) }, [el('span', { text: s.title })]));
    }
    const licFoot = get(DATA, 'modules.Inventory.data.Licensing.Situation');
    document.getElementById('wra-footer').textContent =
      `Gerado em ${fmtTime(get(DATA, 'meta.generatedLocal') ?? get(DATA, 'meta.generatedUtc'))} - ${get(DATA, 'meta.product', '')} ${get(DATA, 'meta.version', '')}${licFoot ? ' — Windows: ' + licFoot : ''} — Desenvolvido por Edsilas`;

    wireExport();
    wireScrollSpy();
  }

  function setActive(id) {
    document.querySelectorAll('.wra-navlink').forEach(a => a.classList.toggle('active', a.getAttribute('href') === `#${id}`));
  }

  // ------------------------------------------------ Exportacao em Markdown
  // O documento e gerado percorrendo TODO o conjunto de dados do relatorio,
  // de forma generica e recursiva. Assim, qualquer informacao presente no
  // relatorio (inclusive campos novos) e exportada sem perda nem omissao.

  const mdEsc = (v) => String(v).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ').trim();

  const mdScalar = (v) => {
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
    if (typeof v === 'string' && /^\/Date\(-?\d+\)\/$/.test(v)) return mdEsc(fmtTime(v));
    return mdEsc(v);
  };

  // Em celulas de tabela, estruturas aninhadas viram JSON compacto — preserva
  // integralmente o conteudo sem quebrar o formato tabular.
  const mdCell = (v) => {
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
    if (typeof v === 'string' && /^\/Date\(-?\d+\)\/$/.test(v)) return mdEsc(fmtTime(v));
    if (typeof v === 'object') return '`' + mdEsc(JSON.stringify(v)) + '`';
    return mdEsc(v);
  };

  const mdRender = (node, title, level, out) => {
    const h = '#'.repeat(Math.min(Math.max(level, 1), 6));
    if (node === null || node === undefined) { out.push(`${h} ${title}`, '', '—', ''); return; }

    if (Array.isArray(node)) {
      out.push(`${h} ${title} (${node.length})`, '');
      if (node.length === 0) { out.push('_Sem registros._', ''); return; }
      const allObjects = node.every(x => x !== null && typeof x === 'object' && !Array.isArray(x));
      if (allObjects) {
        // Uniao de todas as chaves: nenhuma propriedade fica de fora.
        const cols = [];
        for (const row of node) for (const k of Object.keys(row)) if (cols.indexOf(k) < 0) cols.push(k);
        out.push('| ' + cols.map(mdEsc).join(' | ') + ' |');
        out.push('|' + cols.map(() => ' --- ').join('|') + '|');
        for (const row of node) out.push('| ' + cols.map(c => mdCell(row[c])).join(' | ') + ' |');
      } else {
        for (const item of node) out.push('- ' + mdCell(item));
      }
      out.push('');
      return;
    }

    if (typeof node === 'object') {
      out.push(`${h} ${title}`, '');
      const scalars = [], nested = [];
      for (const k of Object.keys(node)) {
        const v = node[k];
        if (v !== null && typeof v === 'object') nested.push([k, v]); else scalars.push([k, v]);
      }
      for (const [k, v] of scalars) out.push(`- **${k}:** ${mdScalar(v)}`);
      if (scalars.length) out.push('');
      for (const [k, v] of nested) mdRender(v, k, level + 1, out);
      return;
    }

    out.push(`${h} ${title}`, '', mdScalar(node), '');
  };

  function buildMarkdownReport() {
    const out = [];
    const meta = DATA.meta ?? {};
    const prioLabel = { critical: 'Crítico', high: 'Alto', medium: 'Médio', low: 'Baixo', info: 'Informativo' };

    // -------- Cabecalho
    out.push('# Windows Resource Auditor — Relatório de Auditoria', '');
    out.push(`- **Máquina:** ${mdScalar(meta.computerName)}`);
    out.push(`- **Produto:** ${mdScalar(meta.product)}`);
    out.push(`- **Versão:** ${mdScalar(meta.version)}`);
    out.push(`- **Gerado em:** ${mdEsc(fmtTime(meta.generatedLocal ?? meta.generatedUtc))}`);
    if (meta.durationMs != null) out.push(`- **Duração da coleta:** ${mdScalar(meta.durationMs)} ms`);
    out.push('');

    // -------- Itens que requerem atencao
    const items = collectAttention();
    out.push('## 1. Itens que Requerem Atenção', '');
    if (!items.length) {
      out.push('Nenhum item requer atenção no momento.', '');
    } else {
      const counts = {};
      for (const it of items) counts[it.prio] = (counts[it.prio] || 0) + 1;
      const resumo = ['critical', 'high', 'medium', 'low', 'info']
        .filter(k => counts[k]).map(k => `${prioLabel[k]}: ${counts[k]}`).join(' · ');
      out.push(`**Total: ${items.length}** (${resumo})`, '');
      out.push('| Prioridade | Componente | Situação | Impacto | Recomendação |');
      out.push('| --- | --- | --- | --- | --- |');
      for (const it of items) {
        out.push(`| ${prioLabel[it.prio] ?? it.prio} | ${mdEsc(it.component)} | ${mdEsc(it.situation)} | ${mdEsc(it.impact ?? '')} | ${mdEsc(it.recommendation ?? '')} |`);
      }
      out.push('');
    }

    // -------- Licenca do Windows (destacada por relevancia; tambem consta no modulo)
    const lic = get(DATA, 'modules.Inventory.data.Licensing');
    if (lic) {
      out.push('## 2. Licença do Windows', '');
      for (const k of Object.keys(lic)) out.push(`- **${k}:** ${mdScalar(lic[k])}`);
      out.push('');
    }

    // -------- Dados completos por modulo
    out.push(`## ${lic ? 3 : 2}. Dados coletados por módulo`, '');
    const modules = DATA.modules ?? {};
    for (const name of Object.keys(modules)) {
      const m = modules[name] ?? {};
      out.push(`### ${mdEsc(name)}`, '');
      const status = (m.success === false) ? 'Com falha' : 'Concluído';
      out.push(`- **Status:** ${status}`);
      if (m.durationMs != null) out.push(`- **Duração:** ${mdScalar(m.durationMs)} ms`);
      const warns = m.warnings ?? [];
      const errs = m.errors ?? [];
      out.push(`- **Avisos:** ${warns.length}`);
      out.push(`- **Erros:** ${errs.length}`);
      out.push('');
      if (warns.length) { out.push('**Avisos:**', ''); for (const w of warns) out.push(`- ${mdCell(w)}`); out.push(''); }
      if (errs.length) { out.push('**Erros:**', ''); for (const e of errs) out.push(`- ${mdCell(e)}`); out.push(''); }
      // Demais campos do envelope do modulo (alem dos ja exibidos acima).
      for (const k of Object.keys(m)) {
        if (['success', 'durationMs', 'warnings', 'errors', 'data'].indexOf(k) >= 0) continue;
        const v = m[k];
        if (v !== null && typeof v === 'object') mdRender(v, k, 4, out);
        else out.push(`- **${k}:** ${mdScalar(v)}`, '');
      }
      if (m.data !== undefined) mdRender(m.data, 'Dados', 4, out);
    }

    // -------- Metadados completos (garante que nenhum campo de meta fique de fora)
    mdRender(meta, `${lic ? 4 : 3}. Metadados do relatório`, 2, out);

    out.push('---', '');
    out.push(`_${mdScalar(meta.product)} ${mdScalar(meta.version)} — Desenvolvido por Edsilas._`);
    return out.join('\n');
  }

  function wireExport() {
    document.getElementById('wra-export-json').addEventListener('click', () => {
      const blob = new Blob([JSON.stringify(DATA, null, 2)], { type: 'application/json' });
      downloadBlob(blob, `wra_${get(DATA, 'meta.computerName', 'host')}.json`);
    });
    const mdBtn = document.getElementById('wra-export-md');
    if (mdBtn) {
      mdBtn.addEventListener('click', () => {
        const md = buildMarkdownReport();
        downloadBlob(new Blob(['\ufeff' + md], { type: 'text/markdown;charset=utf-8' }),
          `wra_${get(DATA, 'meta.computerName', 'host')}.md`);
      });
    }
  }

  function wireScrollSpy() {
    if (typeof IntersectionObserver === 'undefined') return;
    const obs = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) setActive(e.target.id);
    }, { rootMargin: '-40% 0px -55% 0px' });
    sections.forEach(s => obs.observe(s.node));
  }

  function exportTableCsv(table, name) {
    if (!table) return;
    const rows = [...table.querySelectorAll('tr')].filter(tr => !tr.classList.contains('wra-row-hidden'));
    const csv = rows.map(tr => [...tr.children].map(td => {
      // Remove indicadores de ordenação (▲/▼) e normaliza espaços para que o
      // arquivo exportado fique limpo e consistente.
      const t = (td.textContent ?? '').replace(/[\u25B2\u25BC]/g, '').replace(/\s+/g, ' ').trim().replace(/"/g, '""');
      return `"${t}"`;
    }).join(',')).join('\r\n');
    downloadBlob(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }), `wra_${name}.csv`);
  }

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = el('a', { href: url, download: filename });
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();
})();
