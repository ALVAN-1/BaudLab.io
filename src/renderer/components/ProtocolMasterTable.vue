<template>
  <div class="master-table" :class="{ 'master-plain': plain }">
    <h2 class="master-h2">帧结构</h2>
    <div class="master-frame-info">
      <div><b>字节序：</b>{{ protocol.endianness || '小端 (Little-Endian)' }}</div>
      <div><b>校验方式：</b>{{ protocol.checkType || 'CRC16-MODBUS' }}</div>
      <div><b>校验范围：</b>{{ protocol.checkStart || 'SOF' }} → {{ protocol.checkEnd || 'DATA' }}</div>
      <div><b>帧模式：</b>{{ protocol.frameMode || 'fixed' }}</div>
    </div>

    <h2 class="master-h2">模块地址</h2>
    <div class="master-modules">
      <div v-for="m in protocol.modules" :key="m.name" class="master-module-row">
        <span class="master-module-name">{{ m.name }}</span>
        <code class="master-module-addr">{{ m.addressBytes?.join(' ') || m.address || '—' }}</code>
      </div>
      <p v-if="!protocol.modules?.length" class="master-muted">无模块地址定义</p>
    </div>

    <h2 class="master-h2">命令字汇总表</h2>

    <!-- 筛选条（仅默认预览） -->
    <div v-if="showFilters" class="cmd-filter-bar">
      <button
        v-for="cat in ['all', 'general', 'control', 'fault', 'status', 'query', 'config', 'response']"
        :key="cat"
        class="filter-btn"
        :class="{ active: catFilter === cat }"
        @click="catFilter = cat"
      >
        {{ catFilterLabel(cat) }}<span class="filter-count">{{ catCount(cat) }}</span>
      </button>
      <div class="filter-dropdowns">
        <AppSelect v-model="senderFilter" :options="[{ value: '', label: '发送方：全部' }, ...senderOptions.map(s => ({ value: s, label: s }))]" />
        <AppSelect v-model="receiverFilter" :options="[{ value: '', label: '接收方：全部' }, ...receiverOptions.map(r => ({ value: r, label: r }))]" />
      </div>
    </div>

    <!-- 主表 -->
    <div class="cmd-table-wrap">
      <table class="cmd-table">
        <thead>
          <tr>
            <th style="width:80px;">命令字</th>
            <th>指令名称</th>
            <th style="width:100px;">类别</th>
            <th style="width:110px;">发送方</th>
            <th style="width:110px;">接收方</th>
            <th v-if="!expandAll" class="th-bit-toggle" style="width:90px;">查看bit</th>
            <th>数据段格式</th>
            <th style="width:120px;">说明</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="cmd in visibleCommands" :key="cmd.cmd + cmd.name" class="cmd-row">
            <td><span class="cmd-code">{{ cmd.cmd }}</span></td>
            <td>
              <span class="cmd-name">{{ cmd.name }}</span>
              <span v-if="cmd.dir === 'rx'" class="cmd-dir-badge rx">接收</span>
            </td>
            <td><span class="tag" :class="catTagClass(cmd)">{{ cmdCategory(cmd) }}</span></td>
            <td class="cmd-sender">{{ cmd.sender || '—' }}</td>
            <td class="cmd-receiver">{{ cmd.receiver || '—' }}</td>
            <td v-if="!expandAll" class="td-bit-toggle">
              <label v-if="hasBitDetails(cmd)" class="bit-toggle">
                <input type="checkbox" :checked="!!bitOpenMap[cmdKey(cmd)]" @change="toggleBit(cmd)">
                <span class="bit-track"><span class="bit-knob"></span></span>
                <span class="bit-label">{{ bitOpenMap[cmdKey(cmd)] ? '查看解析 ▼' : '查看解析 ▸' }}</span>
              </label>
              <span v-else class="master-muted" style="font-size:11px;">—</span>
            </td>
            <td>
              <!-- 无字段 -->
              <span v-if="!cmd.fields?.length" class="df-noop">0x00（无数据）</span>
              <!-- 字段色块行 -->
              <div v-else class="df-visual">
                <div class="df-field-row">
                  <div
                    v-for="(f, fi) in cmd.fields"
                    :key="f.name"
                    class="df-block"
                    :class="[dfSizeClass(f) + ' df-c' + (fi % DF_COLORS), { 'df-linked': linkedFieldKey === fieldHoverKey(cmd, fi), 'prop-tip': hasPhysProps(f) }]"
                    :data-tip="fieldPropTooltip(f)"
                    @mouseenter="linkedFieldKey = fieldHoverKey(cmd, fi)"
                    @mouseleave="linkedFieldKey = ''"
                  >
                    <span class="df-bname">{{ f.name }}</span>
                    <span class="df-bsize">{{ f.length || 1 }}B · {{ typeLabel(f.type) }}</span>
                  </div>
                </div>
                <!-- 位域/枚举详情：expandAll 模式常驻展开，默认预览按开关展开；
                     颜色与上方字段色块（df-cN）一一对应，悬停任一侧对应字段联动高亮 -->
                <div v-if="hasBitDetails(cmd) && (expandAll || bitOpenMap[cmdKey(cmd)])" class="bit-details-open">
                  <!-- 位域：每个 bit 同时展示 0 / 1 两种含义。
                       悬停触发只在内容（标签/格子）上，行内空白区域不触发改 -->
                  <div
                    v-for="f in cmd.fields.filter(f => f.type === 'bitfield')"
                    :key="f.name"
                    class="bit-byte-row"
                    :class="{ 'bit-row-linked': linkedFieldKey === fieldHoverKey(cmd, cmd.fields.indexOf(f)) }"
                    @mouseleave="linkedFieldKey = ''"
                  >
                    <div
                      class="bit-byte-tag"
                      :class="'df-c' + (cmd.fields.indexOf(f) % DF_COLORS)"
                      @mouseenter="linkedFieldKey = fieldHoverKey(cmd, cmd.fields.indexOf(f))"
                    >{{ f.name }}</div>
                    <div
                      class="bit-byte-bits"
                      :class="'df-c' + (cmd.fields.indexOf(f) % DF_COLORS)"
                      @mouseenter="linkedFieldKey = fieldHoverKey(cmd, cmd.fields.indexOf(f))"
                    >
                      <div
                        v-for="bitNum in [7,6,5,4,3,2,1,0]"
                        :key="bitNum"
                        class="bit-cell"
                        :class="isReservedBit(f, bitNum) ? 'df-bit-reserved' : 'df-bit-defined'"
                      >
                        <span class="bit-bi">Bit{{ bitNum }}</span>
                        <template v-if="!isReservedBit(f, bitNum)">
                          <span
                            v-if="f.bits[bitNum].zero"
                            class="bit-bv-row"
                            :title="`Bit${bitNum} = 0：${f.bits[bitNum].zero}`"
                          >
                            <i class="bit-v-tag">0</i>
                            <span class="bit-bv">{{ f.bits[bitNum].zero }}</span>
                          </span>
                          <span
                            v-if="f.bits[bitNum].one"
                            class="bit-bv-row"
                            :title="`Bit${bitNum} = 1：${f.bits[bitNum].one}`"
                          >
                            <i class="bit-v-tag on">1</i>
                            <span class="bit-bv">{{ f.bits[bitNum].one }}</span>
                          </span>
                        </template>
                        <span v-else class="bit-bv bit-bv-reserved">预留</span>
                      </div>
                    </div>
                  </div>
                  <!-- 枚举 -->
                  <div
                    v-for="f in cmd.fields.filter(f => f.type === 'enum')"
                    :key="f.name"
                    class="bit-byte-row"
                    :class="{ 'bit-row-linked': linkedFieldKey === fieldHoverKey(cmd, cmd.fields.indexOf(f)) }"
                    @mouseleave="linkedFieldKey = ''"
                  >
                    <div
                      class="bit-byte-tag"
                      :class="'df-c' + (cmd.fields.indexOf(f) % DF_COLORS)"
                      @mouseenter="linkedFieldKey = fieldHoverKey(cmd, cmd.fields.indexOf(f))"
                    >{{ f.name }}</div>
                    <div
                      class="bit-byte-bits"
                      :class="'df-c' + (cmd.fields.indexOf(f) % DF_COLORS)"
                      @mouseenter="linkedFieldKey = fieldHoverKey(cmd, cmd.fields.indexOf(f))"
                    >
                      <div v-for="opt in f.enumItems" :key="opt.value" class="bit-cell df-bit-defined">
                        <span class="bit-bi">0x{{ String(opt.value).toUpperCase().padStart(2, '0') }}</span>
                        <span class="bit-bv bit-bv-single">{{ opt.meaning || '—' }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </td>
            <td class="cmd-desc">{{ cmdDesc(cmd) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="visibleCommands.length === 0" class="master-muted" style="text-align:center;padding:20px;">无匹配命令</p>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch } from 'vue';
import AppSelect from './AppSelect.vue';

const props = defineProps({
  protocol: { type: Object, default: null },
  /* 全展开模式（Markdown / PDF 预览）：隐藏查看bit开关，位域/枚举详情常驻展开 */
  expandAll: { type: Boolean, default: false },
  /* 筛选条（仅默认预览） */
  showFilters: { type: Boolean, default: false },
  /* 白纸模式（PDF 样式内嵌）：固定浅色配色，不跟随主题变量 */
  plain: { type: Boolean, default: false },
});

const DF_COLORS = 6;

/* 字段色块 ↔ 位域/枚举/属性详情行 悬停联动。
 * key 必须带命令标识（cmd+name）：索引在不同命令间会撞号，
 * 否则悬停 A 命令的字段1 会误高亮 B 命令的字段1 */
const linkedFieldKey = ref('');

function fieldHoverKey(cmd, idx) {
  return `${cmdKey(cmd)}#${idx}`;
}
const CAT_NAMES = {
  general: '通用', control: '控制', fault: '故障',
  status: '状态', query: '查询', config: '配置', response: '响应',
};
const CAT_TAG_CLASS = {
  general: 'cat-general', control: 'cat-control', fault: 'cat-fault',
  status: 'cat-status', query: 'cat-query', config: 'cat-config', response: 'cat-response',
};
const TYPE_LABELS = {
  bitfield: '位域',
  enum: '枚举',
  raw: '原始数值',
  number: '整数',
  text: '文本',
  binary: '二进制',
};

function typeLabel(t) {
  return TYPE_LABELS[t] || t || '—';
}

/* bit 展开开关状态（按 cmd+name 稳定 key） */
const bitOpenMap = reactive({});

function cmdKey(cmd) {
  return `${cmd.cmd}::${cmd.name}`;
}

function toggleBit(cmd) {
  const key = cmdKey(cmd);
  bitOpenMap[key] = !bitOpenMap[key];
}

/* 切换协议时清空展开状态 */
watch(() => props.protocol, () => {
  Object.keys(bitOpenMap).forEach((k) => delete bitOpenMap[k]);
});

/* 按命令字范围 + 方向推断类别 */
function cmdCatKey(cmd) {
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
function cmdCategory(cmd) {
  return CAT_NAMES[cmdCatKey(cmd)] || '控制';
}
function catTagClass(cmd) {
  return CAT_TAG_CLASS[cmdCatKey(cmd)] || 'cat-control';
}
function catFilterLabel(cat) {
  if (cat === 'all') return '全部';
  return CAT_NAMES[cat] || cat;
}
function catCount(cat) {
  if (!props.protocol?.commands) return 0;
  if (cat === 'all') return props.protocol.commands.length;
  return props.protocol.commands.filter((c) => cmdCatKey(c) === cat).length;
}

/* 有位域/枚举字段才提供 查看bit 开关 */
function hasBitDetails(cmd) {
  return cmd.fields?.some((f) => f.type === 'bitfield' || f.type === 'enum') ?? false;
}
/* 位值为空 → 预留位 */
function isReservedBit(field, bitNum) {
  const b = field.bits?.[bitNum];
  if (!b) return true;
  return !b.one && !b.zero;
}
/* 字段是否配置了物理属性（单位/最小/最大/偏移/备注）——决定色块是否带悬浮气泡 */
function hasPhysProps(f) {
  return !!(f.unit || f.physMin || f.physMax || f.offset || f.remark);
}
/* 字段属性气泡文本：一行一项，未配置的项不出现 */
function fieldPropTooltip(f) {
  const lines = [];
  if (f.unit) lines.push(`单位：${f.unit}`);
  if (f.physMin || f.physMax) lines.push(`物理范围：${f.physMin || '-'} ~ ${f.physMax || '-'}`);
  if (f.offset) lines.push(`偏移量：${f.offset}`);
  if (f.scale !== undefined && f.scale !== null && Number(f.scale) !== 1) lines.push(`缩放：×${f.scale}`);
  if (f.remark) lines.push(`备注：${f.remark}`);
  return lines.join('\n');
}
/* 字段块尺寸样式 */
function dfSizeClass(f) {
  const len = Number(f.length || 1);
  if (len >= 4) return 'df-block-4B';
  if (len === 2) return 'df-block-2B';
  return 'df-block-1B';
}
/* 说明列兜底：无描述数据时用周期信息 */
function cmdDesc(cmd) {
  if (cmd.cycle && cmd.cycle !== '0') return `周期 ${cmd.cycle}ms`;
  return '—';
}

/* 筛选（仅 showFilters 时生效） */
const catFilter = ref('all');
const senderFilter = ref('');
const receiverFilter = ref('');

const senderOptions = computed(() => {
  const s = new Set();
  (props.protocol?.commands || []).forEach((c) => {
    if (c.sender) s.add(c.sender);
  });
  return [...s];
});
const receiverOptions = computed(() => {
  const s = new Set();
  (props.protocol?.commands || []).forEach((c) => {
    if (c.receiver) s.add(c.receiver);
  });
  return [...s];
});

const visibleCommands = computed(() => {
  const cmds = props.protocol?.commands || [];
  if (!props.showFilters) return cmds;
  return cmds.filter((cmd) => {
    if (catFilter.value !== 'all' && cmdCatKey(cmd) !== catFilter.value) return false;
    if (senderFilter.value && !(cmd.sender || '').includes(senderFilter.value)) return false;
    if (receiverFilter.value && !(cmd.receiver || '').includes(receiverFilter.value)) return false;
    return true;
  });
});
</script>

<style scoped>
.master-h2 {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-primary);
  margin-top: 24px;
  margin-bottom: 10px;
  padding-bottom: 6px;
  border-bottom: 1px solid var(--border-light);
  display: flex;
  align-items: center;
  gap: 8px;
}
.master-h2::before {
  content: '';
  display: inline-block;
  width: 3px;
  height: 14px;
  background: var(--accent);
  border-radius: 2px;
}

.master-frame-info {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin-bottom: 8px;
}
.master-frame-info > div {
  font-size: 13px;
  color: var(--text-secondary);
  padding: 8px 12px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-light);
  border-radius: var(--radius-sm);
}

.master-modules { display: flex; flex-direction: column; gap: 4px; }
.master-module-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 6px 12px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-light);
  border-radius: var(--radius-sm);
}
.master-module-name { font-size: 13px; font-weight: 600; color: var(--text-primary); }
.master-module-addr {
  font-family: 'Consolas', monospace;
  font-size: 12px;
  color: var(--accent);
  background: var(--bg-secondary);
  padding: 2px 8px;
  border-radius: 3px;
}

/* 类别标签配色 */
.tag {
  display: inline-block;
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 10px;
  background: var(--bg-secondary);
  color: var(--text-secondary);
}
.tag.cat-general  { background: rgba(39, 166, 68, 0.15);  color: var(--accent-green); }
.tag.cat-control  { background: rgba(59, 130, 246, 0.15); color: var(--accent-blue); }
.tag.cat-fault    { background: rgba(239, 68, 68, 0.15);  color: var(--accent-red); }
.tag.cat-status   { background: rgba(245, 158, 11, 0.15); color: var(--accent-amber); }
.tag.cat-query    { background: rgba(139, 92, 246, 0.15); color: var(--accent-purple); }
.tag.cat-config   { background: rgba(59, 130, 246, 0.15); color: var(--accent-blue); }
.tag.cat-response { background: rgba(139, 92, 246, 0.15); color: var(--accent-purple); }

/* 筛选条 */
.cmd-filter-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin-bottom: 12px;
}
.filter-btn {
  font-size: 12px;
  padding: 4px 12px;
  border-radius: 14px;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.15s ease;
}
.filter-btn:hover { border-color: var(--accent); }
.filter-btn.active {
  background: var(--accent);
  color: #fff;
  border-color: var(--accent);
}
.filter-count { opacity: 0.7; margin-left: 4px; }
.filter-dropdowns {
  display: flex;
  gap: 8px;
  margin-left: auto;
}
.filter-select { width: auto; font-size: 12px; }

/* 主表 */
.cmd-table-wrap {
  overflow-x: auto;
  border: 1px solid var(--border-light);
  border-radius: var(--radius-md);
  background: var(--bg-tertiary);
}
.cmd-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12.5px;
  min-width: 820px;
}
.cmd-table th {
  background: var(--bg-secondary);
  color: var(--text-secondary);
  font-weight: 600;
  padding: 8px 12px;
  text-align: left;
  border-bottom: 2px solid var(--border-color);
  white-space: nowrap;
}
.cmd-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--border-light);
  vertical-align: top;
  color: var(--text-primary);
}
.cmd-table tr:last-child td { border-bottom: none; }
.cmd-table tr:hover td { background: var(--bg-secondary); }

.cmd-code {
  font-family: 'Consolas', monospace;
  font-size: 12px;
  color: var(--accent);
  background: var(--bg-secondary);
  padding: 2px 8px;
  border-radius: 3px;
  white-space: nowrap;
}
.cmd-name { font-weight: 600; }
.cmd-dir-badge {
  font-size: 10px;
  margin-left: 6px;
  padding: 1px 6px;
  border-radius: 8px;
  background: rgba(139, 92, 246, 0.15);
  color: var(--accent-purple);
  vertical-align: middle;
}
.cmd-sender, .cmd-receiver { font-size: 12px; color: var(--text-secondary); }
.cmd-desc { font-size: 11.5px; color: var(--text-tertiary); }
.th-bit-toggle { text-align: left; }
.td-bit-toggle { padding: 6px 8px; vertical-align: middle; }

/* 查看bit 开关 */
.bit-toggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  font-size: 11px;
  color: var(--accent-purple);
  user-select: none;
}
.bit-toggle input { display: none; }
.bit-track {
  width: 28px;
  height: 16px;
  border-radius: 8px;
  background: var(--border-color);
  position: relative;
  transition: background 0.2s ease;
  flex-shrink: 0;
}
.bit-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #fff;
  transition: left 0.2s ease;
}
.bit-toggle input:checked + .bit-track { background: var(--accent-purple); }
.bit-toggle input:checked + .bit-track .bit-knob { left: 14px; }
.bit-label { white-space: nowrap; }

/* 数据段格式色块 */
.df-noop {
  font-size: 12px;
  color: var(--text-tertiary);
  font-family: 'Consolas', monospace;
}
.df-visual { min-width: 0; }
.df-field-row {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.df-block {
  display: inline-flex;
  flex-direction: column;
  padding: 4px 8px;
  border-radius: 4px;
  min-width: 46px;
  border: 1px solid var(--border-light);
  background: var(--bg-secondary);
}
.df-block-1B { min-width: 46px; }
.df-block-2B { min-width: 68px; }
.df-block-4B { min-width: 92px; }
.df-bname { font-size: 11.5px; font-weight: 600; color: var(--text-primary); }
.df-bsize { font-size: 10px; color: var(--text-tertiary); font-family: 'Consolas', monospace; }
.df-c0 { background: rgba(59, 130, 246, 0.12); border-color: rgba(59, 130, 246, 0.35); }
.df-c1 { background: rgba(39, 166, 68, 0.12);  border-color: rgba(39, 166, 68, 0.35); }
.df-c2 { background: rgba(245, 158, 11, 0.12); border-color: rgba(245, 158, 11, 0.35); }
.df-c3 { background: rgba(139, 92, 246, 0.12); border-color: rgba(139, 92, 246, 0.35); }
.df-c4 { background: rgba(239, 68, 68, 0.12);  border-color: rgba(239, 68, 68, 0.35); }
.df-c5 { background: rgba(14, 165, 233, 0.12); border-color: rgba(14, 165, 233, 0.35); }

/* 字段色块 ↔ 详情行 悬停联动：双方同时蓝色脉冲闪烁 */
@keyframes df-link-pulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(59, 130, 246, 0); }
  50% { box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.4); }
}
.df-block.df-linked {
  animation: df-link-pulse 1s ease-in-out infinite;
  border-color: var(--accent-blue) !important;
}
.bit-byte-row.bit-row-linked .bit-byte-tag {
  animation: df-link-pulse 1s ease-in-out infinite;
  border-color: var(--accent-blue) !important;
}
.bit-byte-row.bit-row-linked .bit-cell.df-bit-defined {
  border-color: rgba(59, 130, 246, 0.45);
}

/* 展开的位域/枚举详情 */
.bit-details-open {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px dashed var(--border-color);
}
.bit-byte-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  margin-bottom: 6px;
}
.bit-byte-tag {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 3px;
  white-space: nowrap;
  border: 1px solid var(--border-light);
  background: var(--bg-secondary);
  /* 统一标签列宽度：各行枚举格子从同一竖线起排（约容纳 7 个中文字符，更长则自适应扩展） */
  min-width: 96px;
  box-sizing: border-box;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  text-align: center;
}
.bit-byte-bits {
  display: flex;
  flex-wrap: wrap;
  gap: 3px;
}

/* 详情区与上方字段色块同色（df-cN 双类名特异性高于 .bit-byte-tag 默认底色） */
.bit-byte-tag.df-c0 { background: rgba(59, 130, 246, 0.12); border-color: rgba(59, 130, 246, 0.35); }
.bit-byte-tag.df-c1 { background: rgba(39, 166, 68, 0.12);  border-color: rgba(39, 166, 68, 0.35); }
.bit-byte-tag.df-c2 { background: rgba(245, 158, 11, 0.12); border-color: rgba(245, 158, 11, 0.35); }
.bit-byte-tag.df-c3 { background: rgba(139, 92, 246, 0.12); border-color: rgba(139, 92, 246, 0.35); }
.bit-byte-tag.df-c4 { background: rgba(239, 68, 68, 0.12);  border-color: rgba(239, 68, 68, 0.35); }
.bit-byte-tag.df-c5 { background: rgba(14, 165, 233, 0.12); border-color: rgba(14, 165, 233, 0.35); }

.bit-byte-bits.df-c0 .bit-cell.df-bit-defined { background: rgba(59, 130, 246, 0.07); border-color: rgba(59, 130, 246, 0.25); }
.bit-byte-bits.df-c1 .bit-cell.df-bit-defined { background: rgba(39, 166, 68, 0.07);  border-color: rgba(39, 166, 68, 0.25); }
.bit-byte-bits.df-c2 .bit-cell.df-bit-defined { background: rgba(245, 158, 11, 0.07); border-color: rgba(245, 158, 11, 0.25); }
.bit-byte-bits.df-c3 .bit-cell.df-bit-defined { background: rgba(139, 92, 246, 0.07); border-color: rgba(139, 92, 246, 0.25); }
.bit-byte-bits.df-c4 .bit-cell.df-bit-defined { background: rgba(239, 68, 68, 0.07);  border-color: rgba(239, 68, 68, 0.25); }
.bit-byte-bits.df-c5 .bit-cell.df-bit-defined { background: rgba(14, 165, 233, 0.07); border-color: rgba(14, 165, 233, 0.25); }

.bit-cell {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  padding: 3px 6px;
  border-radius: 3px;
  min-width: 60px;
  max-width: 132px;
  border: 1px solid var(--border-light);
}
.bit-cell.df-bit-defined { background: var(--bg-secondary); }
.bit-cell.df-bit-reserved {
  background: transparent;
  border-style: dashed;
  opacity: 0.55;
}
.bit-bi { font-size: 9.5px; color: var(--text-tertiary); font-family: 'Consolas', monospace; text-align: center; }

/* 单个 bit 的 0/1 含义行：小方块数值标签 + 含义文本 */
.bit-bv-row {
  display: flex;
  align-items: center;
  gap: 3px;
  min-width: 0;
  margin-top: 2px;
}
.bit-v-tag {
  flex-shrink: 0;
  width: 12px;
  height: 12px;
  border-radius: 3px;
  font-size: 9px;
  font-weight: 700;
  font-style: normal;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(100, 116, 139, 0.16);
  color: var(--text-tertiary);
}
.bit-v-tag.on {
  background: rgba(59, 130, 246, 0.18);
  color: var(--accent-blue);
}
.bit-bv {
  font-size: 10.5px;
  color: var(--text-primary);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.bit-bv-single { text-align: center; }
.bit-bv-reserved { text-align: center; color: var(--text-tertiary); font-size: 10px; }

/* 字段物理属性悬浮气泡：配置了 单位/范围/偏移/备注 的色块（.prop-tip）
 * 悬浮时在上方弹出，一行一项；纯 CSS 实现，不占任何版面 */
.prop-tip {
  position: relative;
  cursor: help;
}
.prop-tip::after {
  content: attr(data-tip);
  position: absolute;
  bottom: calc(100% + 6px);
  left: 0;
  background: #1f2937;
  color: #fff;
  font-size: 11px;
  line-height: 1.7;
  padding: 6px 10px;
  border-radius: 6px;
  white-space: pre-line;
  width: max-content;
  max-width: 280px;
  text-align: left;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.22);
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.15s ease;
  pointer-events: none;
  z-index: 30;
}
.prop-tip:hover::after {
  opacity: 1;
  visibility: visible;
}

.master-muted { font-size: 13px; color: var(--text-tertiary); }

/* ==================== 白纸模式（PDF 样式内嵌）：固定浅色配色 ==================== */
.master-plain .master-h2 { color: #1a1a1a; border-bottom-color: #e5e7eb; }
.master-plain .master-h2::before { background: #5e6ad2; }
.master-plain .master-frame-info > div {
  color: #444;
  background: #fafafa;
  border-color: #e5e7eb;
}
.master-plain .master-module-row { background: #fafafa; border-color: #e5e7eb; }
.master-plain .master-module-name { color: #1a1a1a; }
.master-plain .master-module-addr { color: #3f4a9e; background: #eef0fa; }
.master-plain .tag { background: #f3f4f6; color: #6b7280; }
.master-plain .tag.cat-general  { background: rgba(39, 166, 68, 0.15);  color: #15803d; }
.master-plain .tag.cat-control  { background: rgba(59, 130, 246, 0.15); color: #1d4ed8; }
.master-plain .tag.cat-fault    { background: rgba(239, 68, 68, 0.15);  color: #b91c1c; }
.master-plain .tag.cat-status   { background: rgba(245, 158, 11, 0.15); color: #b45309; }
.master-plain .tag.cat-query,
.master-plain .tag.cat-response { background: rgba(139, 92, 246, 0.15); color: #6d28d9; }
.master-plain .cmd-table-wrap { border-color: #e5e7eb; background: #fff; }
.master-plain .cmd-table th {
  background: #eef0fa;
  color: #3f4a9e;
  border-bottom: 2px solid #c9cff0;
}
.master-plain .cmd-table td { color: #1a1a1a; border-bottom-color: #f0f0f0; }
.master-plain .cmd-table tr:hover td { background: #fafafa; }
.master-plain .cmd-code { color: #3f4a9e; background: #eef0fa; }
.master-plain .cmd-name { color: #1a1a1a; }
.master-plain .cmd-dir-badge { color: #6d28d9; }
.master-plain .cmd-sender, .master-plain .cmd-receiver { color: #555; }
.master-plain .cmd-desc { color: #888; }
.master-plain .df-noop { color: #888; }
.master-plain .df-block { border-color: #e5e7eb; background: #fff; }
.master-plain .df-bname { color: #1a1a1a; }
.master-plain .df-bsize { color: #888; }
.master-plain .bit-details-open { border-top-color: #e5e7eb; }
.master-plain .bit-byte-tag { border-color: #e5e7eb; background: #fafafa; }
.master-plain .bit-byte-tag.df-c0 { background: rgba(59, 130, 246, 0.10); border-color: rgba(59, 130, 246, 0.30); }
.master-plain .bit-byte-tag.df-c1 { background: rgba(39, 166, 68, 0.10);  border-color: rgba(39, 166, 68, 0.30); }
.master-plain .bit-byte-tag.df-c2 { background: rgba(245, 158, 11, 0.10); border-color: rgba(245, 158, 11, 0.30); }
.master-plain .bit-byte-tag.df-c3 { background: rgba(139, 92, 246, 0.10); border-color: rgba(139, 92, 246, 0.30); }
.master-plain .bit-byte-tag.df-c4 { background: rgba(239, 68, 68, 0.10);  border-color: rgba(239, 68, 68, 0.30); }
.master-plain .bit-byte-tag.df-c5 { background: rgba(14, 165, 233, 0.10); border-color: rgba(14, 165, 233, 0.30); }
.master-plain .bit-cell { border-color: #e5e7eb; }
.master-plain .bit-cell.df-bit-defined { background: #fafafa; }
.master-plain .bit-v-tag { background: rgba(100, 116, 139, 0.14); color: #6b7280; }
.master-plain .bit-v-tag.on { background: rgba(59, 130, 246, 0.15); color: #1d4ed8; }
.master-plain .bit-bv-reserved { color: #888; }
.master-plain .bit-bi { color: #888; }
.master-plain .bit-bv { color: #1a1a1a; }
.master-plain .master-muted { color: #888; }
</style>
