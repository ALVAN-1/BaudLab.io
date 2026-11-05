<template>
  <div class="view">
    <div class="view-header">
      <div>
        <h1 class="view-title">协议预览</h1>
        <p class="view-subtitle">浏览协议完整文档，支持 Markdown / PDF 样式切换</p>
      </div>
      <div class="view-actions">
        <button v-if="selectedProtocol" class="btn btn-primary btn-small" :disabled="exporting" @click="exportDoc">{{ exporting ? '导出中…' : '导出协议文档' }}</button>
        <button v-if="selectedProtocol" class="btn btn-secondary btn-small" @click="copyMarkdown">复制 Markdown</button>
        <button v-if="selectedProtocol && viewMode === 'pdf'" class="btn btn-secondary btn-small" @click="printDoc">打印</button>
      </div>
    </div>

    <div class="preview-layout">
      <!-- 左侧协议列表 -->
      <aside class="proto-sidebar">
        <div class="sidebar-search">
          <input type="text" class="input" v-model="searchText" placeholder="搜索协议…" />
        </div>
        <div class="proto-list">
          <div
            v-for="p in filteredProtocols"
            :key="p.id"
            class="proto-item"
            :class="{ active: selectedId === p.id }"
            @click="selectProtocol(p)"
          >
            <div class="proto-item-name">{{ p.name }}</div>
            <div class="proto-item-meta">
              <span class="proto-ver">{{ p.version }}</span>
              <span class="proto-cmd-count">{{ p.cmdCount }} 条命令</span>
            </div>
          </div>
          <div v-if="filteredProtocols.length === 0" class="proto-empty">
            {{ loading ? '加载中…' : '暂无协议' }}
          </div>
        </div>
      </aside>

      <!-- 右侧文档区 -->
      <div class="doc-container">
        <!-- 格式切换 -->
        <div v-if="selectedProtocol" class="doc-toolbar">
          <div class="tab-bar" style="margin-bottom: 0;">
            <button :class="['tab-btn', { active: viewMode === 'default' }]" @click="viewMode = 'default'">默认预览</button>
            <button :class="['tab-btn', { active: viewMode === 'md' }]" @click="viewMode = 'md'">Markdown</button>
            <button :class="['tab-btn', { active: viewMode === 'pdf' }]" @click="viewMode = 'pdf'">PDF 样式</button>
          </div>
        </div>

        <!-- 未选择协议 -->
        <div v-if="!selectedProtocol" class="doc-empty">
          <p>从左侧选择一个协议查看文档</p>
        </div>

        <!-- 默认预览：cmd-master-table 扁平大表 -->
        <div v-else-if="viewMode === 'default'" class="doc-scroll master-view">
          <h1 class="doc-title">{{ selectedProtocol.name }}</h1>
          <p class="doc-version">版本 {{ selectedProtocol.version }} · 更新于 {{ selectedProtocol.updated_at }}</p>
          <p v-if="selectedProtocol.protoDesc" class="doc-desc">{{ selectedProtocol.protoDesc }}</p>

          <ProtocolMasterTable :protocol="selectedProtocol" show-filters />
        </div>

        <!-- Markdown 视图：与默认预览同一呈现，字段内容全部展开 -->
        <div v-else-if="viewMode === 'md'" class="doc-scroll master-view">
          <h1 class="doc-title">{{ selectedProtocol.name }}</h1>
          <p class="doc-version">版本 {{ selectedProtocol.version }} · 更新于 {{ selectedProtocol.updated_at }}</p>
          <p v-if="selectedProtocol.protoDesc" class="doc-desc">{{ selectedProtocol.protoDesc }}</p>

          <ProtocolMasterTable :protocol="selectedProtocol" expand-all />
        </div>

        <!-- PDF 样式视图 -->
        <div v-else class="doc-scroll pdf-view">
          <div class="pdf-page" id="pdf-print-area">
            <!-- 顶部封面横幅 -->
            <div class="pdf-cover">
              <h1>{{ selectedProtocol.name }}</h1>
              <p class="pdf-cover-sub">串口协议文档</p>
              <div class="pdf-cover-meta">
                <span>版本<strong>v{{ selectedProtocol.version }}</strong></span>
                <span>{{ selectedProtocol.commands?.length || 0 }} 条命令</span>
                <span>{{ selectedProtocol.modules?.length || 0 }} 个模块</span>
              </div>
            </div>

            <div class="pdf-body">
              <p v-if="selectedProtocol.protoDesc" class="pdf-desc">{{ selectedProtocol.protoDesc }}</p>

              <!-- 与默认预览同一呈现，字段内容全部展开 -->
              <ProtocolMasterTable :protocol="selectedProtocol" expand-all plain />

              <div class="pdf-footer">
                <p>BaudLab · 文档生成于 {{ new Date().toLocaleString('zh-CN') }}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="toast.show" class="save-toast" :class="toast.type">{{ toast.msg }}</div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import ProtocolMasterTable from '../components/ProtocolMasterTable.vue';

const props = defineProps({
  /* 由 App.vue 传入：本页签是否处于激活状态（每次切到预览页都刷新协议列表） */
  active: { type: Boolean, default: false },
});

const hasElectron = typeof window !== 'undefined' && typeof window.electronAPI !== 'undefined';

const loading = ref(false);
const protocols = ref([]);
const selectedId = ref(null);
const selectedProtocol = ref(null);
const viewMode = ref('default');
const searchText = ref('');

const filteredProtocols = computed(() => {
  if (!searchText.value) return protocols.value;
  const q = searchText.value.toLowerCase();
  return protocols.value.filter((p) => p.name.toLowerCase().includes(q));
});

const FIELD_DESCRIPTIONS = {
  sof: '帧头标识',
  src: '源地址',
  dst: '目标地址',
  ver: '协议版本',
  cmd: '命令字',
  ctr: '控制字',
  seq: '序列号',
  tid: '事务ID',
  len: '数据长度',
  data: '数据负载',
  chk: '校验码',
  eof: '帧尾标识',
};

function fieldDesc(f) {
  return FIELD_DESCRIPTIONS[String(f).toLowerCase()] || '—';
}

/* 字段类型中文标签（与预览表格/配置页一致） */
const FIELD_TYPE_LABELS = {
  bitfield: '位域',
  enum: '枚举',
  raw: '原始数值',
  number: '多字节整数',
  text: '文本/JSON',
  binary: '二进制段',
};

function fieldTypeLabel(t) {
  return FIELD_TYPE_LABELS[t] || t || '—';
}

async function loadProtocols() {
  if (!hasElectron) return;
  loading.value = true;
  try {
    const res = await window.electronAPI.db.query('SELECT id, name, version, config_json, byte_order, check_method, check_start, check_end, frame_mode, updated_at FROM protocols ORDER BY id');
    if (!res.success || !res.rows) return;
    const list = [];
    for (const p of res.rows) {
      let config = {};
      try { config = JSON.parse(p.config_json || '{}'); } catch (_) {}
      const cmdRes = await window.electronAPI.db.query('SELECT COUNT(*) as cnt FROM commands WHERE protocol_id = ?', [p.id]);
      list.push({
        id: p.id,
        name: p.name,
        version: p.version,
        protoDesc: config.protoDesc || '',
        endianness: config.endianness || (p.byte_order === 'little' ? '小端 (Little-Endian)' : '大端 (Big-Endian)'),
        checkType: config.checkType || p.check_method || 'CRC16-MODBUS',
        checkStart: config.checkStartField || p.check_start || 'SOF',
        checkEnd: config.checkEndField || p.check_end || 'DATA',
        frameMode: p.frame_mode || 'fixed',
        fieldOrder: config.fieldOrder || ['sof', 'src', 'dst', 'ver', 'cmd', 'ctr', 'seq', 'tid', 'len', 'data', 'chk', 'eof'],
        fieldConfig: config.fieldConfig || {},
        config_json: p.config_json,
        updated_at: p.updated_at,
        cmdCount: cmdRes.success ? cmdRes.rows[0].cnt : 0,
      });
    }
    protocols.value = list;
    /* 保留当前选中项；若尚未选择或已被删除，则选中第一个 */
    const current = list.find((p) => p.id === selectedId.value);
    if (current) await selectProtocol(current);
    else if (list.length > 0) await selectProtocol(list[0]);
  } finally {
    loading.value = false;
  }
}

async function selectProtocol(p) {
  selectedId.value = p.id;
  if (!hasElectron) return;

  const [cmdRes, modRes] = await Promise.all([
    window.electronAPI.db.query('SELECT * FROM commands WHERE protocol_id = ? ORDER BY id', [p.id]),
    window.electronAPI.db.query('SELECT * FROM modules WHERE protocol_id = ? ORDER BY id', [p.id]),
  ]);

  const commands = [];
  if (cmdRes.success && cmdRes.rows) {
    for (const c of cmdRes.rows) {
      let cmdData = {};
      try { cmdData = JSON.parse(c.config_json || '{}'); } catch (_) {}
      commands.push({
        cmd: c.code,
        cmdBytes: cmdData.cmdBytes || [c.code.replace('0x', '')],
        name: c.name,
        sender: c.sender || '',
        receiver: c.receiver || '',
        dir: c.direction === 'send' ? 'tx' : 'rx',
        cycle: String(c.period_ms || 0),
        fields: cmdData.fields || [],
      });
    }
  }

  const modules = [];
  if (modRes.success && modRes.rows) {
    for (const m of modRes.rows) {
      modules.push({
        name: m.name,
        address: m.address,
        addressBytes: m.address ? m.address.split(' ') : ['00'],
      });
    }
  }

  selectedProtocol.value = {
    ...p,
    commands,
    modules: modules.length > 0 ? modules : [{ name: '主控制器', addressBytes: ['01'] }],
  };
}

function buildMarkdown() {
  const p = selectedProtocol.value;
  if (!p) return '';
  let md = `# ${p.name}\n\n`;
  md += `> 版本 ${p.version} · 更新于 ${p.updated_at}\n\n`;
  if (p.protoDesc) md += `${p.protoDesc}\n\n`;

  md += `## 帧结构\n\n`;
  md += `| 属性 | 值 |\n|---|---|\n`;
  md += `| 字节序 | ${p.endianness} |\n`;
  md += `| 校验方式 | ${p.checkType} |\n`;
  md += `| 校验范围 | ${p.checkStart} → ${p.checkEnd} |\n`;
  md += `| 帧模式 | ${p.frameMode} |\n\n`;

  if (p.fieldOrder?.length) {
    md += `| # | 字段 | 说明 |\n|---|---|---|\n`;
    p.fieldOrder.forEach((f, i) => {
      md += `| ${i + 1} | \`${f}\` | ${fieldDesc(f)} |\n`;
    });
    md += '\n';
  }

  md += `## 模块地址\n\n`;
  if (p.modules?.length) {
    md += `| 模块名称 | 地址 |\n|---|---|\n`;
    p.modules.forEach((m) => {
      md += `| ${m.name} | \`${m.addressBytes?.join(' ') || m.address || '—'}\` |\n`;
    });
    md += '\n';
  } else {
    md += `无模块地址定义\n\n`;
  }

  md += `## 命令列表\n\n`;
  for (const cmd of p.commands) {
    md += `### ${cmd.name} \`${cmd.cmd}\`\n\n`;
    md += `- 方向：${cmd.dir === 'tx' ? '发送 →' : '← 接收'}\n`;
    md += `- 发送方：${cmd.sender || '—'}\n`;
    md += `- 接收方：${cmd.receiver || '—'}\n`;
    if (cmd.cycle && cmd.cycle !== '0') md += `- 周期：${cmd.cycle}ms\n`;
    md += '\n';

    if (cmd.fields?.length) {
      md += `| 字段名 | 长度 | 类型 | 缩放 | 单位 | 物理最小 | 物理最大 | 偏移量 | 备注 |\n|---|---|---|---|---|---|---|---|---|\n`;
      for (const f of cmd.fields) {
        md += `| ${f.name} | ${f.length} | ${fieldTypeLabel(f.type)} | ${f.scale ?? 1} | ${f.unit || '/'} | ${f.physMin || '/'} | ${f.physMax || '/'} | ${f.offset || '/'} | ${f.remark || '/'} |\n`;
      }
      md += '\n';
    }

    /* 位域：数据结构为 f.bits[bitNum] = { bit, zero, one }，按 Bit7→Bit0 输出 0/1 双含义 */
    const bitFields = cmd.fields?.filter((f) => f.type === 'bitfield' && Array.isArray(f.bits)) || [];
    if (bitFields.length) {
      md += `**位域定义**\n\n`;
      for (const f of bitFields) {
        md += `*${f.name}*\n\n`;
        md += `| 位 | 为 0 含义 | 为 1 含义 |\n|---|---|---|\n`;
        for (const bitNum of [7, 6, 5, 4, 3, 2, 1, 0]) {
          const b = f.bits[bitNum];
          if (!b || (!b.zero && !b.one)) continue; /* 未定义的位不输出 */
          md += `| Bit${bitNum} | ${b.zero || '—'} | ${b.one || '—'} |\n`;
        }
        md += '\n';
      }
    }

    /* 枚举：数据结构为 f.enumItems = [{ value, meaning }]，value 为十六进制数值 */
    const enumFields = cmd.fields?.filter((f) => f.type === 'enum' && Array.isArray(f.enumItems)) || [];
    if (enumFields.length) {
      md += `**枚举定义**\n\n`;
      for (const f of enumFields) {
        md += `*${f.name}*\n\n`;
        md += `| 值 | 含义 |\n|---|---|\n`;
        for (const o of f.enumItems) {
          const v = String(o.value ?? '').replace(/^0x/i, '');
          md += `| 0x${v.toUpperCase().padStart(2, '0')} | ${o.meaning || '—'} |\n`;
        }
        md += '\n';
      }
    }
  }

  return md;
}

async function copyMarkdown() {
  const md = buildMarkdown();
  try {
    await navigator.clipboard.writeText(md);
  } catch (_) {
    const ta = document.createElement('textarea');
    ta.value = md;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  }
}

function printDoc() {
  window.print();
}

/* ==================== 导出协议文档 ====================
 * 导出格式取决于当前预览模式：默认预览 → HTML、Markdown → .md、PDF 样式 → .pdf
 * 导出内容与预览主表（ProtocolMasterTable）保持一致：
 * 帧结构 / 模块地址 / 命令字汇总表（类别 tag、数据段字段色块、位域 0-1 双含义、枚举、字段物理属性） */

const exporting = ref(false);
const toast = ref({ show: false, msg: '', type: 'success' });
let pvToastTimer = null;

function showToast(msg, type = 'success', duration = 2500) {
  toast.value = { show: true, msg, type };
  clearTimeout(pvToastTimer);
  pvToastTimer = setTimeout(() => { toast.value.show = false; }, duration);
}

/* 类别推断：与预览主表 cmdCatKey 完全一致 */
const PV_CAT_NAMES = {
  general: '通用', control: '控制', fault: '故障',
  status: '状态', query: '查询', config: '配置', response: '响应',
};

function pvCatKey(cmd) {
  const code = parseInt(String(cmd.cmd).replace('0x', ''), 16);
  if (Number.isNaN(code)) return 'control';
  if (cmd.dir === 'rx') return 'response';
  if (code >= 0x0100 && code < 0x0200) return 'general';
  if (code >= 0x0200 && code < 0x0300) return 'control';
  if (code >= 0x0300 && code < 0x0400) return 'fault';
  if (code >= 0x0400 && code < 0x0500) return 'status';
  if (code >= 0x0500 && code < 0x0600) return 'query';
  if (code >= 0x0600 && code < 0x0700) return 'config';
  return 'control';
}
function pvCatName(cmd) {
  return PV_CAT_NAMES[pvCatKey(cmd)] || '控制';
}

/* 字段物理属性行：与预览色块悬浮气泡一致（静态文档中以文字随色块呈现） */
function fieldPropLines(f) {
  const lines = [];
  if (f.unit) lines.push(`单位：${f.unit}`);
  if (f.physMin || f.physMax) lines.push(`物理范围：${f.physMin || '-'} ~ ${f.physMax || '-'}`);
  if (f.offset) lines.push(`偏移量：${f.offset}`);
  if (f.scale !== undefined && f.scale !== null && Number(f.scale) !== 1) lines.push(`缩放：×${f.scale}`);
  if (f.remark) lines.push(`备注：${f.remark}`);
  return lines;
}

function escHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/* 字段色块最小宽度（与预览 dfSizeClass 对应） */
function dfSizeMin(f) {
  const len = Number(f.length || 1);
  if (len >= 4) return 92;
  if (len === 2) return 68;
  return 46;
}

/* ---------- Markdown 导出：与预览主表逐节对应 ---------- */
function buildPreviewMarkdown(p) {
  let md = `# ${p.name}\n\n`;
  md += `> 版本 ${p.version} · 更新于 ${p.updated_at}\n\n`;
  if (p.protoDesc) md += `${p.protoDesc}\n\n`;

  md += `## 帧结构\n\n`;
  md += `| 属性 | 值 |\n|---|---|\n`;
  md += `| 字节序 | ${p.endianness || '小端 (Little-Endian)'} |\n`;
  md += `| 校验方式 | ${p.checkType || 'CRC16-MODBUS'} |\n`;
  md += `| 校验范围 | ${p.checkStart || 'SOF'} → ${p.checkEnd || 'DATA'} |\n`;
  md += `| 帧模式 | ${p.frameMode || 'fixed'} |\n\n`;

  md += `## 模块地址\n\n`;
  if (p.modules?.length) {
    md += `| 模块名称 | 地址 |\n|---|---|\n`;
    p.modules.forEach((m) => {
      md += `| ${m.name} | \`${m.addressBytes?.join(' ') || m.address || '—'}\` |\n`;
    });
    md += '\n';
  } else {
    md += `无模块地址定义\n\n`;
  }

  md += `## 命令字汇总表\n\n`;
  for (const cmd of p.commands || []) {
    const fields = cmd.fields || [];
    md += `### ${cmd.name} \`${cmd.cmd}\`\n\n`;
    md += `- 类别：${pvCatName(cmd)}　方向：${cmd.dir === 'tx' ? '发送 →' : '← 接收'}\n`;
    md += `- 发送方：${cmd.sender || '—'}　接收方：${cmd.receiver || '—'}\n`;
    md += `- 说明：${cmd.cycle && cmd.cycle !== '0' ? `周期 ${cmd.cycle}ms` : '—'}\n\n`;

    if (fields.length) {
      md += `**数据段格式**：${fields.map((f) => `${f.name}(${f.length || 1}B·${fieldTypeLabel(f.type)})`).join(' + ')}\n\n`;
      md += `| 字段名 | 长度 | 类型 | 缩放 | 单位 | 物理最小 | 物理最大 | 偏移量 | 备注 |\n|---|---|---|---|---|---|---|---|---|\n`;
      for (const f of fields) {
        md += `| ${f.name} | ${f.length || 1} | ${fieldTypeLabel(f.type)} | ${f.scale ?? 1} | ${f.unit || '/'} | ${f.physMin || '/'} | ${f.physMax || '/'} | ${f.offset || '/'} | ${f.remark || '/'} |\n`;
      }
      md += '\n';
    } else {
      md += `**数据段格式**：0x00（无数据）\n\n`;
    }

    /* 位域：Bit7→Bit0 全部位输出，未定义位标注「预留」，与预览一致 */
    const bitFields = fields.filter((f) => f.type === 'bitfield' && Array.isArray(f.bits));
    if (bitFields.length) {
      md += `**位域定义**\n\n`;
      for (const f of bitFields) {
        md += `*${f.name}*\n\n`;
        md += `| 位 | 为 0 含义 | 为 1 含义 |\n|---|---|---|\n`;
        for (const bitNum of [7, 6, 5, 4, 3, 2, 1, 0]) {
          const b = f.bits[bitNum];
          if (!b || (!b.zero && !b.one)) md += `| Bit${bitNum} | 预留 | 预留 |\n`;
          else md += `| Bit${bitNum} | ${b.zero || '—'} | ${b.one || '—'} |\n`;
        }
        md += '\n';
      }
    }

    /* 枚举 */
    const enumFields = fields.filter((f) => f.type === 'enum' && Array.isArray(f.enumItems));
    if (enumFields.length) {
      md += `**枚举定义**\n\n`;
      for (const f of enumFields) {
        md += `*${f.name}*\n\n`;
        md += `| 值 | 含义 |\n|---|---|\n`;
        for (const o of f.enumItems) {
          const v = String(o.value ?? '').replace(/^0x/i, '');
          md += `| 0x${v.toUpperCase().padStart(2, '0')} | ${o.meaning || '—'} |\n`;
        }
        md += '\n';
      }
    }
  }
  return md;
}

/* ---------- HTML 导出：独立单文件，排版镜像预览主表（浅色白纸配色，兼作 PDF 打印源） ---------- */
function buildPreviewHTML(p) {
  const now = new Date().toLocaleString('zh-CN');

  const frameInfoRows = [
    ['字节序', p.endianness || '小端 (Little-Endian)'],
    ['校验方式', p.checkType || 'CRC16-MODBUS'],
    ['校验范围', `${p.checkStart || 'SOF'} → ${p.checkEnd || 'DATA'}`],
    ['帧模式', p.frameMode || 'fixed'],
  ].map(([k, v]) => `<div><b>${escHtml(k)}：</b>${escHtml(v)}</div>`).join('');

  const moduleRowsHtml = (p.modules || []).map((m) =>
    `<div class="pv-module-row"><span class="pv-module-name">${escHtml(m.name)}</span><code class="pv-module-addr">${escHtml(m.addressBytes?.join(' ') || m.address || '—')}</code></div>`
  ).join('') || '<p class="pv-muted">无模块地址定义</p>';

  /* 字段色块（物理属性以小字随块展示，保证静态文档信息完整） */
  function dfBlockHtml(f, fi) {
    const props = fieldPropLines(f);
    return `<div class="df-block df-c${fi % 6}" style="min-width:${dfSizeMin(f)}px">`
      + `<span class="df-bname">${escHtml(f.name)}</span>`
      + `<span class="df-bsize">${f.length || 1}B · ${escHtml(fieldTypeLabel(f.type))}</span>`
      + (props.length ? `<span class="df-bprops">${props.map(escHtml).join('<br>')}</span>` : '')
      + `</div>`;
  }

  /* 位域 / 枚举详情行（Bit7→Bit0 全部输出，未定义位=预留虚线格） */
  function bitDetailHtml(cmd) {
    const fields = cmd.fields || [];
    const details = fields.filter((f) => f.type === 'bitfield' || f.type === 'enum');
    if (!details.length) return '';
    let html = '<div class="bit-details-open">';
    for (const f of details) {
      const ci = fields.indexOf(f) % 6;
      html += `<div class="bit-byte-row"><div class="bit-byte-tag df-c${ci}">${escHtml(f.name)}</div><div class="bit-byte-bits df-c${ci}">`;
      if (f.type === 'bitfield' && Array.isArray(f.bits)) {
        for (const bitNum of [7, 6, 5, 4, 3, 2, 1, 0]) {
          const b = f.bits[bitNum];
          if (!b || (!b.zero && !b.one)) {
            html += `<div class="bit-cell df-bit-reserved"><span class="bit-bi">Bit${bitNum}</span><span class="bit-bv bit-bv-reserved">预留</span></div>`;
          } else {
            html += `<div class="bit-cell df-bit-defined"><span class="bit-bi">Bit${bitNum}</span>`;
            if (b.zero) html += `<span class="bit-bv-row"><i class="bit-v-tag">0</i><span class="bit-bv">${escHtml(b.zero)}</span></span>`;
            if (b.one) html += `<span class="bit-bv-row"><i class="bit-v-tag on">1</i><span class="bit-bv">${escHtml(b.one)}</span></span>`;
            html += `</div>`;
          }
        }
      } else if (f.type === 'enum' && Array.isArray(f.enumItems)) {
        for (const o of f.enumItems) {
          const v = String(o.value ?? '').replace(/^0x/i, '').toUpperCase().padStart(2, '0');
          html += `<div class="bit-cell df-bit-defined"><span class="bit-bi">0x${escHtml(v)}</span><span class="bit-bv bit-bv-single">${escHtml(o.meaning || '—')}</span></div>`;
        }
      }
      html += `</div></div>`;
    }
    html += '</div>';
    return html;
  }

  const cmdRowsHtml = (p.commands || []).map((cmd) => {
    const fields = cmd.fields || [];
    let dfHtml;
    if (!fields.length) {
      dfHtml = `<span class="df-noop">0x00（无数据）</span>`;
    } else {
      dfHtml = `<div class="df-field-row">${fields.map((f, i) => dfBlockHtml(f, i)).join('')}</div>${bitDetailHtml(cmd)}`;
    }
    const desc = cmd.cycle && cmd.cycle !== '0' ? `周期 ${escHtml(cmd.cycle)}ms` : '—';
    return `<tr>`
      + `<td><span class="cmd-code">${escHtml(cmd.cmd)}</span></td>`
      + `<td><span class="cmd-name">${escHtml(cmd.name)}</span>${cmd.dir === 'rx' ? '<span class="cmd-dir-badge">接收</span>' : ''}</td>`
      + `<td><span class="tag cat-${pvCatKey(cmd)}">${pvCatName(cmd)}</span></td>`
      + `<td class="cmd-side">${escHtml(cmd.sender || '—')}</td>`
      + `<td class="cmd-side">${escHtml(cmd.receiver || '—')}</td>`
      + `<td><div class="df-visual">${dfHtml}</div></td>`
      + `<td class="cmd-desc">${desc}</td>`
      + `</tr>`;
  }).join('');

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>${escHtml(p.name)} - 协议文档</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Microsoft YaHei', 'PingFang SC', sans-serif; color: #1a1a1a; font-size: 13px; line-height: 1.6; padding: 32px 40px; background: #fff; }
.pv-doc { max-width: 1080px; margin: 0 auto; }
.pv-title { font-size: 24px; font-weight: 700; }
.pv-meta { color: #888; font-size: 12px; margin: 4px 0 12px; }
.pv-desc { font-size: 13px; color: #444; background: #eef0fa; border-left: 4px solid #5e6ad2; padding: 10px 14px; border-radius: 0 6px 6px 0; margin-bottom: 8px; }
.pv-h2 { font-size: 16px; font-weight: 600; margin: 24px 0 10px; padding-bottom: 6px; border-bottom: 1px solid #e5e7eb; display: flex; align-items: center; gap: 8px; }
.pv-h2::before { content: ''; display: inline-block; width: 3px; height: 14px; background: #5e6ad2; border-radius: 2px; }
.pv-frame-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.pv-frame-grid > div { font-size: 12.5px; color: #444; padding: 8px 12px; background: #fafafa; border: 1px solid #e5e7eb; border-radius: 6px; }
.pv-module-row { display: flex; align-items: center; gap: 12px; padding: 6px 12px; background: #fafafa; border: 1px solid #e5e7eb; border-radius: 6px; margin-bottom: 4px; }
.pv-module-name { font-weight: 600; font-size: 13px; }
.pv-module-addr { font-family: Consolas, monospace; font-size: 12px; color: #3f4a9e; background: #eef0fa; padding: 2px 8px; border-radius: 3px; }
table.cmd-table { width: 100%; border-collapse: collapse; font-size: 12px; border: 1px solid #e5e7eb; }
.cmd-table th { background: #eef0fa; color: #3f4a9e; font-weight: 600; padding: 8px 10px; text-align: left; border-bottom: 2px solid #c9cff0; white-space: nowrap; }
.cmd-table td { padding: 8px 10px; border-bottom: 1px solid #f0f0f0; vertical-align: top; }
.cmd-code { font-family: Consolas, monospace; color: #3f4a9e; background: #eef0fa; padding: 2px 8px; border-radius: 3px; white-space: nowrap; }
.cmd-name { font-weight: 600; }
.cmd-dir-badge { font-size: 10px; margin-left: 6px; padding: 1px 6px; border-radius: 8px; background: rgba(139,92,246,0.15); color: #6d28d9; }
.cmd-side { font-size: 12px; color: #555; }
.cmd-desc { font-size: 11px; color: #888; }
.tag { display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 10px; background: #f3f4f6; color: #6b7280; white-space: nowrap; }
.tag.cat-general { background: rgba(39,166,68,0.15); color: #15803d; }
.tag.cat-control { background: rgba(59,130,246,0.15); color: #1d4ed8; }
.tag.cat-fault { background: rgba(239,68,68,0.15); color: #b91c1c; }
.tag.cat-status { background: rgba(245,158,11,0.15); color: #b45309; }
.tag.cat-query { background: rgba(139,92,246,0.15); color: #6d28d9; }
.tag.cat-config { background: rgba(59,130,246,0.15); color: #1d4ed8; }
.tag.cat-response { background: rgba(139,92,246,0.15); color: #6d28d9; }
.df-visual { min-width: 0; }
.df-field-row { display: flex; flex-wrap: wrap; gap: 4px; }
.df-block { display: inline-flex; flex-direction: column; padding: 4px 8px; border-radius: 4px; border: 1px solid #e5e7eb; background: #fff; }
.df-bname { font-size: 11.5px; font-weight: 600; }
.df-bsize { font-size: 10px; color: #888; font-family: Consolas, monospace; }
.df-bprops { font-size: 9.5px; color: #6b7280; margin-top: 3px; line-height: 1.5; border-top: 1px dashed #e5e7eb; padding-top: 2px; }
.df-c0 { background: rgba(59,130,246,0.10); border-color: rgba(59,130,246,0.30); }
.df-c1 { background: rgba(39,166,68,0.10); border-color: rgba(39,166,68,0.30); }
.df-c2 { background: rgba(245,158,11,0.10); border-color: rgba(245,158,11,0.30); }
.df-c3 { background: rgba(139,92,246,0.10); border-color: rgba(139,92,246,0.30); }
.df-c4 { background: rgba(239,68,68,0.10); border-color: rgba(239,68,68,0.30); }
.df-c5 { background: rgba(14,165,233,0.10); border-color: rgba(14,165,233,0.30); }
.df-noop { font-size: 12px; color: #888; font-family: Consolas, monospace; }
.bit-details-open { margin-top: 8px; padding-top: 8px; border-top: 1px dashed #e5e7eb; }
.bit-byte-row { display: flex; align-items: flex-start; gap: 8px; margin-bottom: 6px; }
.bit-byte-tag { font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 3px; white-space: nowrap; min-width: 96px; display: inline-flex; align-items: center; justify-content: center; border: 1px solid #e5e7eb; background: #fafafa; }
.bit-byte-tag.df-c0 { background: rgba(59,130,246,0.10); border-color: rgba(59,130,246,0.30); }
.bit-byte-tag.df-c1 { background: rgba(39,166,68,0.10); border-color: rgba(39,166,68,0.30); }
.bit-byte-tag.df-c2 { background: rgba(245,158,11,0.10); border-color: rgba(245,158,11,0.30); }
.bit-byte-tag.df-c3 { background: rgba(139,92,246,0.10); border-color: rgba(139,92,246,0.30); }
.bit-byte-tag.df-c4 { background: rgba(239,68,68,0.10); border-color: rgba(239,68,68,0.30); }
.bit-byte-tag.df-c5 { background: rgba(14,165,233,0.10); border-color: rgba(14,165,233,0.30); }
.bit-byte-bits { display: flex; flex-wrap: wrap; gap: 3px; }
.bit-byte-bits.df-c0 .bit-cell.df-bit-defined { background: rgba(59,130,246,0.07); border-color: rgba(59,130,246,0.25); }
.bit-byte-bits.df-c1 .bit-cell.df-bit-defined { background: rgba(39,166,68,0.07); border-color: rgba(39,166,68,0.25); }
.bit-byte-bits.df-c2 .bit-cell.df-bit-defined { background: rgba(245,158,11,0.07); border-color: rgba(245,158,11,0.25); }
.bit-byte-bits.df-c3 .bit-cell.df-bit-defined { background: rgba(139,92,246,0.07); border-color: rgba(139,92,246,0.25); }
.bit-byte-bits.df-c4 .bit-cell.df-bit-defined { background: rgba(239,68,68,0.07); border-color: rgba(239,68,68,0.25); }
.bit-byte-bits.df-c5 .bit-cell.df-bit-defined { background: rgba(14,165,233,0.07); border-color: rgba(14,165,233,0.25); }
.bit-cell { display: flex; flex-direction: column; padding: 3px 6px; border-radius: 3px; min-width: 60px; max-width: 132px; border: 1px solid #e5e7eb; }
.bit-cell.df-bit-defined { background: #fafafa; }
.bit-cell.df-bit-reserved { background: transparent; border-style: dashed; opacity: 0.55; }
.bit-bi { font-size: 9.5px; color: #888; font-family: Consolas, monospace; text-align: center; }
.bit-bv-row { display: flex; align-items: center; gap: 3px; margin-top: 2px; min-width: 0; }
.bit-v-tag { flex-shrink: 0; width: 12px; height: 12px; border-radius: 3px; font-size: 9px; font-weight: 700; font-style: normal; display: flex; align-items: center; justify-content: center; background: rgba(100,116,139,0.14); color: #6b7280; }
.bit-v-tag.on { background: rgba(59,130,246,0.15); color: #1d4ed8; }
.bit-bv { font-size: 10.5px; color: #1a1a1a; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.bit-bv-single { text-align: center; }
.bit-bv-reserved { text-align: center; color: #888; font-size: 10px; }
.pv-muted { color: #888; font-size: 12px; }
.pv-footer { margin-top: 32px; padding-top: 12px; border-top: 2px solid #c9cff0; text-align: center; font-size: 11px; color: #4a56c0; }
@media print { body { padding: 0; } }
</style>
</head>
<body>
<div class="pv-doc">
  <h1 class="pv-title">${escHtml(p.name)}</h1>
  <p class="pv-meta">串口协议文档 · 版本 v${escHtml(p.version)} · 更新于 ${escHtml(p.updated_at || '')} · ${(p.commands || []).length} 条命令</p>
  ${p.protoDesc ? `<p class="pv-desc">${escHtml(p.protoDesc)}</p>` : ''}

  <h2 class="pv-h2">帧结构</h2>
  <div class="pv-frame-grid">${frameInfoRows}</div>

  <h2 class="pv-h2">模块地址</h2>
  ${moduleRowsHtml}

  <h2 class="pv-h2">命令字汇总表</h2>
  <table class="cmd-table">
    <thead>
      <tr>
        <th style="width:80px;">命令字</th>
        <th>指令名称</th>
        <th style="width:70px;">类别</th>
        <th style="width:100px;">发送方</th>
        <th style="width:100px;">接收方</th>
        <th>数据段格式</th>
        <th style="width:90px;">说明</th>
      </tr>
    </thead>
    <tbody>${cmdRowsHtml}</tbody>
  </table>

  <div class="pv-footer">BaudLab · 文档生成于 ${escHtml(now)}</div>
</div>
</body>
</html>`;
}

/* ---------- 按预览模式分发导出 ---------- */
async function exportDoc() {
  const p = selectedProtocol.value;
  if (!p || exporting.value) return;
  exporting.value = true;
  try {
    const baseName = `${String(p.name).replace(/[\\/:*?"<>|]/g, '_')}-协议文档`;
    let format;
    let fileName;
    let content;
    if (viewMode.value === 'md') {
      format = 'md';
      fileName = `${baseName}.md`;
      content = buildPreviewMarkdown(p);
    } else if (viewMode.value === 'pdf') {
      format = 'pdf';
      fileName = `${baseName}.pdf`;
      content = buildPreviewHTML(p);
    } else {
      format = 'html';
      fileName = `${baseName}.html`;
      content = buildPreviewHTML(p);
    }
    const res = await window.electronAPI.export.saveFile({ defaultFileName: fileName, format, content });
    if (res?.success) showToast(`已导出：${fileName}`, 'success');
    else if (!res?.canceled) showToast(res?.error || '导出失败', 'error');
  } catch (e) {
    showToast('导出失败：' + (e?.message || e), 'error');
  } finally {
    exporting.value = false;
  }
}

onMounted(() => { loadProtocols(); });

/* 每次切到本页签都重新加载：发布生效/保存草稿后新协议才能出现在预览中（v-show 常驻不重新挂载） */
watch(() => props.active, (isActive) => {
  if (isActive) loadProtocols();
});
</script>

<style scoped>
.preview-layout {
  display: flex;
  gap: 16px;
  flex: 1;
  min-height: 0;
  height: calc(100% - 130px);
}

/* 左侧协议列表 */
.proto-sidebar {
  width: 220px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  overflow: hidden;
}

.sidebar-search {
  padding: 10px;
  border-bottom: 1px solid var(--border-light);
}
.sidebar-search .input { font-size: 12px; }

.proto-list {
  flex: 1;
  overflow-y: auto;
  padding: 4px;
}

.proto-item {
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: background 0.15s ease;
  margin-bottom: 2px;
}
.proto-item:hover { background: var(--bg-tertiary); }
.proto-item.active {
  background: var(--bg-tertiary);
  border-left: 3px solid var(--accent);
  padding-left: 9px;
}

.proto-item-name {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.proto-item-meta {
  display: flex;
  gap: 8px;
  margin-top: 3px;
}
.proto-ver { font-size: 11px; color: var(--accent); }
.proto-cmd-count { font-size: 11px; color: var(--text-tertiary); }

.proto-empty {
  padding: 20px;
  text-align: center;
  color: var(--text-tertiary);
  font-size: 13px;
}

/* 右侧文档区 */
.doc-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.doc-toolbar {
  margin-bottom: 12px;
}

.doc-empty {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-tertiary);
  font-size: 15px;
}

.doc-scroll {
  flex: 1;
  overflow-y: auto;
  padding: 4px;
}

.doc-title {
  font-size: 24px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 4px;
}

.doc-version {
  font-size: 13px;
  color: var(--text-tertiary);
  margin-bottom: 16px;
}

.doc-desc {
  font-size: 14px;
  color: var(--text-secondary);
  margin-bottom: 24px;
  line-height: 1.6;
}

/* 默认预览：cmd-master-table，自适应铺满容器宽度 */
.master-view { max-width: none; }

.master-view .doc-title {
  font-size: 24px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 4px;
}
.master-view .doc-version {
  font-size: 13px;
  color: var(--text-tertiary);
  margin-bottom: 16px;
}
.master-view .doc-desc {
  font-size: 14px;
  color: var(--text-secondary);
  margin-bottom: 24px;
  line-height: 1.6;
}


/* PDF 样式视图 */
.pdf-view {
  background: var(--bg-tertiary);
  padding: 20px;
}

.pdf-page {
  background: white;
  color: #1a1a1a;
  /* 自适应铺满容器宽度（打印时由 @media print 规则另行处理） */
  max-width: none;
  width: 100%;
  margin: 0 auto;
  padding: 0;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.15);
  font-family: 'Georgia', 'Times New Roman', serif;
  font-size: 14px;
  line-height: 1.7;
  overflow: hidden;
}

/* 顶部品牌色横幅 */
.pdf-cover {
  background: linear-gradient(135deg, #5e6ad2 0%, #4a56c0 100%);
  color: white;
  padding: 40px 56px 36px;
  position: relative;
}
.pdf-cover::after {
  content: '';
  position: absolute;
  bottom: -1px;
  left: 0;
  right: 0;
  height: 4px;
  background: linear-gradient(90deg, #828fff, #5e6ad2, #4a56c0);
}
.pdf-cover h1 {
  font-size: 26px;
  font-weight: 700;
  margin: 0 0 8px;
  letter-spacing: 1px;
}
.pdf-cover .pdf-cover-sub {
  font-size: 13px;
  opacity: 0.9;
  margin: 0;
}
.pdf-cover .pdf-cover-meta {
  display: flex;
  gap: 20px;
  margin-top: 16px;
  font-size: 12px;
  opacity: 0.85;
}
.pdf-cover .pdf-cover-meta span {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.pdf-cover .pdf-cover-meta strong {
  font-weight: 600;
  background: rgba(255,255,255,0.2);
  padding: 2px 8px;
  border-radius: 4px;
  font-family: 'Consolas', monospace;
}

.pdf-body {
  padding: 32px 56px 48px;
}

.pdf-desc {
  font-size: 14px;
  color: #444;
  background: #eef0fa;
  border-left: 4px solid #5e6ad2;
  padding: 12px 16px;
  border-radius: 0 6px 6px 0;
  margin-bottom: 24px;
  line-height: 1.6;
}

.pdf-footer {
  margin-top: 32px;
  padding-top: 12px;
  border-top: 2px solid #c9cff0;
  text-align: center;
  font-size: 11px;
  color: #4a56c0;
  font-family: 'Arial', sans-serif;
}

@media print {
  .view-header, .doc-toolbar, .proto-sidebar { display: none !important; }
  .preview-layout { display: block !important; }
  .doc-container { display: block !important; }
  .pdf-view { background: white; padding: 0; }
  .pdf-page { box-shadow: none; max-width: none; }
}
</style>
