<template>
  <div class="app-select" :class="{ 'is-disabled': disabled, 'is-open': open }" ref="rootRef">
    <button
      type="button"
      class="app-select-trigger"
      :disabled="disabled"
      @click="toggle"
      @keydown.down.prevent="onKeydown('down')"
      @keydown.up.prevent="onKeydown('up')"
      @keydown.enter.prevent="onKeydown('enter')"
      @keydown.escape.prevent="close"
    >
      <span class="app-select-label" :class="{ 'is-placeholder': !selectedOption }">
        {{ selectedOption ? selectedOption.label : (placeholder || '请选择') }}
      </span>
      <svg class="app-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><use href="#i-chevron-down" /></svg>
    </button>

    <Teleport to="body">
      <Transition name="app-select-pop">
        <div v-if="open" class="app-select-panel" ref="panelRef" :style="panelStyle" @mousedown.prevent>
          <div
            v-for="(opt, i) in normalized"
            :key="i"
            class="app-select-option"
            :class="{ 'is-selected': isSelected(opt), 'is-disabled': opt.disabled, 'is-hovered': i === hoverIdx && !opt.disabled }"
            @mouseenter="hoverIdx = i"
            @click="pick(opt)"
          >
            <span class="app-select-opt-label">{{ opt.label }}</span>
            <svg v-if="isSelected(opt)" class="app-select-check" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><use href="#i-check" /></svg>
          </div>
          <div v-if="!normalized.length" class="app-select-empty">暂无选项</div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<script setup>
/* 全应用统一自绘下拉框：替代原生 select（原生展开列表无法美化）。
 * - options: [{ value, label, disabled? }] 或原始 string/number 数组
 * - v-model 值保持原始类型（number 不会被转成 string）
 * - 兼容原生用法：update:modelValue + change 事件、disabled、placeholder
 */
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  modelValue: { type: [String, Number, Object, null], default: '' },
  options: { type: Array, default: () => [] },
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  /* 面板最大高度 */
  maxHeight: { type: Number, default: 280 },
});

const emit = defineEmits(['update:modelValue', 'change']);

const rootRef = ref(null);
const panelRef = ref(null);
const open = ref(false);
const hoverIdx = ref(-1);
const panelStyle = ref({});

const normalized = computed(() =>
  props.options.map((opt) =>
    typeof opt === 'object' && opt !== null
      ? { value: opt.value, label: String(opt.label ?? opt.value), disabled: !!opt.disabled }
      : { value: opt, label: String(opt), disabled: false },
  ),
);

const selectedOption = computed(() =>
  normalized.value.find((o) => o.value === props.modelValue && String(o.value) === String(props.modelValue))
    || normalized.value.find((o) => o.value === props.modelValue)
    || null,
);

function isSelected(opt) {
  if (props.modelValue === opt.value) return true;
  /* 兼容 undefined/null 与 '' 互相等价的场景 */
  return props.modelValue == null && opt.value === '';
}

function toggle() {
  if (props.disabled) return;
  open.value ? close() : show();
}

function show() {
  open.value = true;
  hoverIdx.value = normalized.value.findIndex((o) => isSelected(o));
  nextTick(positionPanel);
  document.addEventListener('mousedown', onOutside, true);
  document.addEventListener('scroll', onDocScroll, true);
  window.addEventListener('resize', close);
}

function close() {
  if (!open.value) return;
  open.value = false;
  document.removeEventListener('mousedown', onOutside, true);
  document.removeEventListener('scroll', onDocScroll, true);
  window.removeEventListener('resize', close);
}

/* 面板定位：与触发器同宽（最小 160），向下空间不足时向上翻转 */
function positionPanel() {
  const root = rootRef.value;
  const panel = panelRef.value;
  if (!root || !panel) return;
  const rect = root.getBoundingClientRect();
  const panelH = panel.offsetHeight || props.maxHeight;
  const spaceBelow = window.innerHeight - rect.bottom;
  const spaceAbove = rect.top;
  const maxH = Math.min(props.maxHeight, Math.max(120, Math.max(spaceBelow, spaceAbove) - 12));
  const flipUp = spaceBelow < Math.min(panelH, maxH) + 12 && spaceAbove > spaceBelow;
  panelStyle.value = {
    left: `${Math.round(rect.left)}px`,
    top: flipUp ? 'auto' : `${Math.round(rect.bottom + 4)}px`,
    bottom: flipUp ? `${Math.round(window.innerHeight - rect.top + 4)}px` : 'auto',
    minWidth: `${Math.max(Math.round(rect.width), 160)}px`,
    maxHeight: `${maxH}px`,
  };
  /* 选中项滚入可视区 */
  nextTick(() => {
    const el = panel.querySelector('.app-select-option.is-selected');
    if (el) el.scrollIntoView({ block: 'nearest' });
  });
}

function onDocScroll() {
  if (open.value) close();
}

function onOutside(e) {
  if (rootRef.value?.contains(e.target) || panelRef.value?.contains(e.target)) return;
  close();
}

function pick(opt) {
  if (opt.disabled) return;
  emit('update:modelValue', opt.value);
  emit('change', opt.value);
  close();
}

function onKeydown(dir) {
  if (props.disabled) return;
  if (dir === 'down' || dir === 'up') {
    if (!open.value) { show(); return; }
    const n = normalized.value.length;
    if (!n) return;
    let i = hoverIdx.value;
    for (let step = 0; step < n; step++) {
      i = dir === 'down' ? (i + 1) % n : (i - 1 + n) % n;
      if (!normalized.value[i].disabled) break;
    }
    hoverIdx.value = i;
    nextTick(() => {
      panelRef.value?.querySelectorAll('.app-select-option')[i]?.scrollIntoView({ block: 'nearest' });
    });
  } else if (dir === 'enter') {
    if (!open.value) { show(); return; }
    const opt = normalized.value[hoverIdx.value];
    if (opt && !opt.disabled) pick(opt);
  }
}

/* modelValue 外部变化时收起（保持触发器文案同步） */
watch(() => props.modelValue, () => { if (open.value) nextTick(positionPanel); });
watch(() => props.disabled, (d) => { if (d) close(); });

onBeforeUnmount(close);
</script>

<style scoped>
.app-select { position: relative; display: inline-flex; width: 100%; min-width: 0; }

/* 触发器：与 .input 同一视觉语言 */
.app-select-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  min-width: 0;
  padding: 7px 30px 7px 12px;
  font-size: 13px;
  font-family: inherit;
  color: var(--text-primary);
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm, 6px);
  cursor: pointer;
  text-align: left;
  transition: border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease;
}
.app-select-trigger:hover { border-color: var(--border-light); background: var(--bg-hover); }
.app-select-trigger:focus-visible,
.app-select.is-open .app-select-trigger {
  outline: none;
  border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--accent-glow);
}
.app-select.is-disabled .app-select-trigger {
  opacity: 0.45;
  cursor: not-allowed;
}

.app-select-label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-select-label.is-placeholder { color: var(--text-muted); }

.app-select-chevron {
  flex-shrink: 0;
  color: var(--text-tertiary);
  transition: transform 0.18s ease;
}
.app-select.is-open .app-select-chevron { transform: rotate(180deg); }

/* ── 浮层面板（Teleport 到 body） ── */
.app-select-panel {
  position: fixed;
  z-index: 10002; /* 高于 .save-toast(10001) 与弹窗遮罩 */
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 4px;
  background: var(--bg-elevated);
  border: 1px solid var(--border-light);
  border-radius: 10px;
  box-shadow: 0 12px 36px rgba(0, 0, 0, 0.28), 0 2px 8px rgba(0, 0, 0, 0.18);
}

.app-select-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 10px;
  border-radius: 6px;
  font-size: 12.5px;
  line-height: 1.45;
  color: var(--text-secondary);
  cursor: pointer;
  transition: background-color 0.1s ease, color 0.1s ease;
}
.app-select-option.is-hovered {
  background: var(--bg-hover);
  color: var(--text-primary);
}
.app-select-option.is-selected {
  background: rgba(94, 106, 210, 0.14);
  color: var(--accent-hover);
  font-weight: 600;
}
.app-select-option.is-disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.app-select-opt-label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-select-check { flex-shrink: 0; }
.app-select-empty {
  padding: 14px 10px;
  text-align: center;
  font-size: 12px;
  color: var(--text-muted);
}

/* ── 进出场动画 ── */
.app-select-pop-enter-active,
.app-select-pop-leave-active {
  transition: opacity 0.14s ease, transform 0.14s ease;
}
.app-select-pop-enter-from,
.app-select-pop-leave-to {
  opacity: 0;
  transform: translateY(-4px) scale(0.985);
}
</style>
