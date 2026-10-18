import { Fragment, useEffect, useState } from 'react';
import QuarantineEditor from './QuarantineEditor';
import { cachedJSON, useJSON } from './useJSON';
import type { ReactNode } from 'react';
import {
  ArrowDownRight, ArrowRight, ArrowUpRight, CalendarDays, ChartNoAxesCombined,
  Check, ChevronDown, ChevronLeft, ChevronRight, CircleCheck, Download,
  ExternalLink, GitBranch, Info, Layers, LayoutDashboard, Menu, RefreshCw, Search,
  ShieldCheck, ShoppingBag, Store, TrendingUp, Trophy, Users, UtensilsCrossed, Wallet, X,
} from 'lucide-react';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

type Tab = 'overview' | 'restaurants' | 'dishes' | 'customers' | 'quality' | 'runs';
type Metric = 'revenue' | 'orders';
type Grain = 'day' | 'week' | 'month';
type Summary = { revenue: number; orders: number; average_order: number; units: number };
type Processing = { raw_rows: number; loaded: number; quarantined: number; duplicates: number; unaccounted: number };
type Bootstrap = { bounds: { start: string | null; end: string | null }; restaurants: { restaurant_id: string; restaurant_name: string }[]; latest_run: { run_id: number; finished_at: string } | null; processing: Processing };
type RestaurantRow = { restaurant_id: string; restaurant_name: string; city: string; orders: number; revenue: number; average_order: number; units: number };
type HourlyOrders = { hour: number; orders: number };
type DishRow = { dish_id: string; dish_name: string; orders: number; units: number; revenue: number };
type CustomerRow = { customer_id: string; full_name: string; orders: number; units: number; revenue: number; average_order: number; last_order_date: string; portion_rank: number; dishes: DishRow[] };
type Dashboard = { summary: Summary; previous: Summary; period: { start: string; end: string }; trend: { date: string; revenue: number; orders: number }[]; restaurants: RestaurantRow[]; orders_by_hour: HourlyOrders[]; dishes: (DishRow & { unit_price: number | null })[]; fulfillment: { type: string; orders: number; revenue: number }[]; fetched_at: string };
type Reason = { reason: string; affected_raw_rows: number; description: string };
type Quality = { summary: Processing; reasons: Reason[]; checks: { check_name: string; passed: boolean }[]; profile: { column_name: string; raw_rows: number; empty_rows: number; placeholder_rows: number; distinct_values: number }[] };
type RawRow = { raw_id: number; source_record: Record<string, string | null>; reasons: string[] };
type Quarantine = { rows: RawRow[]; total: number; page: number; page_size: number };
type Run = { run_id: number; started_at: string; finished_at: string; duration_seconds: number; previous_run_id: number | null; all_metrics_equal: boolean | null; metrics: Processing & { total_amount: number; quality_checks_passed: boolean } };

const number = new Intl.NumberFormat('ru-RU');
const rubles = new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'RUB', maximumFractionDigits: 0 });
const preciseRubles = new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'RUB', maximumFractionDigits: 2 });
const n = (value: number) => number.format(value);
const money = (value: number) => rubles.format(value);
const short = (value: number) => Math.abs(value) >= 1e6 ? `${(value / 1e6).toLocaleString('ru-RU', { maximumFractionDigits: 1 })} млн` : Math.abs(value) >= 1e3 ? `${(value / 1e3).toLocaleString('ru-RU', { maximumFractionDigits: 0 })} тыс.` : n(value);
const day = (value: string) => new Date(`${value.slice(0, 10)}T12:00:00`).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' }).replace('.', '');
const timestamp = (value: string) => new Date(value).toLocaleString('ru-RU', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
const dateShift = (value: string, days: number) => { const d = new Date(`${value}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + days); return d.toISOString().slice(0, 10); };
const fulfillment = [
  { key: 'delivery', name: 'Доставка курьером', color: '#315c48' },
  { key: 'pickup', name: 'Самовывоз', color: '#b6d879' },
  { key: 'unassigned', name: 'Курьер не назначен', color: '#e6bd7b' },
  { key: 'unknown', name: 'Способ не указан', color: '#dce2db' },
];
const tabs: { key: Tab; name: string; icon: typeof LayoutDashboard }[] = [
  { key: 'overview', name: 'Обзор', icon: LayoutDashboard },
  { key: 'restaurants', name: 'Рестораны', icon: Store },
  { key: 'dishes', name: 'Блюда', icon: UtensilsCrossed },
  { key: 'customers', name: 'Клиенты', icon: Users },
  { key: 'quality', name: 'Качество данных', icon: ShieldCheck },
  { key: 'runs', name: 'История загрузок', icon: GitBranch },
];

function Empty({ title = 'Заказов за этот период нет', text = 'Попробуйте выбрать другой период или ресторан.' }: { title?: string; text?: string }) {
  return <div className="empty"><span><Search size={24} /></span><strong>{title}</strong><p>{text}</p></div>;
}
function Loading() { return <div className="loading-state" role="status"><RefreshCw className="spin" size={22} /><span>Получаем данные…</span></div>; }
function ErrorBox({ text, retry }: { text: string; retry: () => void }) {
  return <div className="error-box" role="alert"><Info size={19} /><span>{text}</span><button onClick={retry}>Повторить</button></div>;
}
function Panel({ title, subtitle, action, children, className = '' }: { title: string; subtitle?: string; action?: ReactNode; children: ReactNode; className?: string }) {
  return <section className={`panel ${className}`}><div className="panel-heading"><div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div>{action}</div>{children}</section>;
}
function Stat({ label, value, previous, icon, index }: { label: string; value: number; previous: number; icon: ReactNode; index: number }) {
  const delta = previous > 0 ? (value - previous) / previous * 100 : null;
  return <section className={`stat ${index === 0 ? 'stat-featured' : ''}`}><div className="stat-label">{label}<span className="stat-icon">{icon}</span></div>
    <div className="stat-value">{index === 0 ? money(value) : index === 2 ? preciseRubles.format(value) : n(value)}</div>
    <div className="stat-foot">{delta !== null ? <><span className={`delta ${delta < 0 ? 'down' : ''}`}>{delta < 0 ? <ArrowDownRight size={14} /> : <ArrowUpRight size={14} />}{Math.abs(delta).toLocaleString('ru-RU', { maximumFractionDigits: 1 })}%</span><span>к предыдущему периоду</span></> : <><span className="tiny-dot" /><span>За выбранный период</span></>}</div>
  </section>;
}
function RestaurantTable({ rows, onSelect, compact = false }: { rows: RestaurantRow[]; onSelect: (id: string) => void; compact?: boolean }) {
  const [sort, setSort] = useState<'revenue' | 'orders' | 'average_order' | 'units'>('revenue');
  const sorted = [...rows].sort((a, b) => b[sort] - a[sort]);
  if (!rows.length) return <Empty />;
  return <div className="table-scroll"><table className="data-table restaurant-table"><thead><tr><th>Ресторан</th>{([['orders', 'Заказы'], ['revenue', 'Выручка'], ['average_order', 'Средний чек'], ...(!compact ? [['units', 'Блюд']] : [])] as [typeof sort, string][]).map(([key, title]) => <th key={key}><button className={key === sort ? 'sort-active' : ''} onClick={() => setSort(key)}>{title}{sort === key && <ChevronDown size={12} />}</button></th>)}</tr></thead><tbody>{(compact ? sorted.slice(0, 5) : sorted).map((r, i) => <tr key={r.restaurant_id}><td><button className="restaurant-name" onClick={() => onSelect(r.restaurant_id)}><span className={`restaurant-mark mark-${i % 4}`}><Store size={15} /></span><span><strong>{r.restaurant_name}</strong><small>{r.city}</small></span></button></td><td>{n(r.orders)}</td><td className="emphasis">{money(r.revenue)}</td><td>{preciseRubles.format(r.average_order)}</td>{!compact && <td>{n(r.units)}</td>}</tr>)}</tbody></table></div>;
}
function OrderTimeDistribution({ restaurants, selected, onSelect, start, end, revision, retry }: {
  restaurants: Bootstrap['restaurants']; selected: string[]; onSelect: (ids: string[]) => void;
  start: string; end: string; revision: number; retry: () => void;
}) {
  const params = new URLSearchParams({ start, end });
  [...selected].sort().forEach(id => params.append('restaurant', id));
  const { data, error } = useJSON<{ rows: HourlyOrders[] }>(`/api/orders-by-hour?${params}`, revision);
  const rows = data?.rows || [];
  const restaurantName = selected.length ? restaurants.filter(r => selected.includes(r.restaurant_id)).map(r => r.restaurant_name).join(', ') : 'Все рестораны';
  const total = rows.reduce((sum, row) => sum + row.orders, 0);
  const peak = Math.max(0, ...rows.map(row => row.orders));
  const hourLabel = (hour: number) => `${String(hour).padStart(2, '0')}:00`;
  return <Panel title="Когда заказывают чаще" subtitle={`${restaurantName} · Распределение заказов по часам суток`} className="order-distribution" action={data && !error && <span className="count-tag">{n(total)} заказов</span>}>
    <details className="distribution-filter" onKeyDown={event => {
      if (event.key === 'Escape') { event.currentTarget.open = false; event.currentTarget.querySelector('summary')?.focus(); }
    }}>
      <summary aria-label="Рестораны для графика"><Store size={15} /><span>Рестораны для графика</span><strong>{selected.length ? `Выбрано: ${selected.length}` : 'Все рестораны'}</strong><ChevronDown size={14} /></summary>
      <div className="distribution-filter-options">
        <button className="text-button" disabled={!selected.length} onClick={() => onSelect([])}>Все рестораны</button>
        <div className="distribution-checkboxes" role="group" aria-label="Выбор ресторанов для графика">
          {restaurants.map(r => <label key={r.restaurant_id}><input type="checkbox" value={r.restaurant_id} checked={selected.includes(r.restaurant_id)} onChange={event => onSelect(event.target.checked ? [...selected, r.restaurant_id] : selected.filter(id => id !== r.restaurant_id))} /><span>{r.restaurant_name}</span></label>)}
        </div>
      </div>
    </details>
    <p className="distribution-filter-hint">Выбор ресторанов действует только на этот график. Период задаётся вверху страницы.</p>
    {error ? <ErrorBox text={error} retry={retry} /> : !data ? <Loading /> : !total ? <Empty /> : <>
      <div className="chart-topline"><div><span className="distribution-dot" />Количество заказов</div><div><span className="distribution-dot peak" />Пиковые часы</div></div>
      <div className="hourly-chart" role="img" aria-label="Распределение заказов по часам суток">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={rows} accessibilityLayer margin={{ top: 16, right: 8, bottom: 8, left: 0 }} barCategoryGap="18%">
            <CartesianGrid strokeDasharray="3 5" vertical={false} stroke="#e9ede7" />
            <XAxis dataKey="hour" tickFormatter={hourLabel} interval={2} axisLine={false} tickLine={false} tick={{ fill: '#6f7967', fontSize: 10 }} dy={8} />
            <YAxis allowDecimals={false} tickFormatter={value => short(Number(value))} axisLine={false} tickLine={false} tick={{ fill: '#6f7967', fontSize: 10 }} width={48} />
            <Tooltip cursor={{ fill: '#f2f6e9' }} content={({ active, payload, label }) => active && payload?.length ? <div className="chart-tooltip"><span>{hourLabel(Number(label))}–{hourLabel((Number(label) + 1) % 24)}</span><strong>{n(Number(payload[0].value))} заказов</strong><span className="distribution-share">{(Number(payload[0].value) / total * 100).toLocaleString('ru-RU', { maximumFractionDigits: 1 })}% за выбранный период</span></div> : null} />
            <Bar dataKey="orders" name="Заказы" radius={[3, 3, 0, 0]} isAnimationActive={false}>
              {rows.map(row => <Cell key={row.hour} fill={row.orders === peak ? '#315c48' : '#b6cf98'} />)}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="distribution-note">Один столбец — один час. Заказы за выбранные дни суммируются по времени оформления, без пересчёта часового пояса.</p>
    </>}
  </Panel>;
}
function DishRanking({ rows, compact = false }: { rows: DishRow[]; compact?: boolean }) {
  const [metric, setMetric] = useState<'units' | 'revenue'>('units');
  const sorted = [...rows].sort((a, b) => b[metric] - a[metric]);
  const max = sorted[0]?.[metric] || 1;
  return <><div className="ranking-controls"><span>{metric === 'units' ? 'Количество порций' : 'Выручка заказов'}</span><div className="segmented small"><button className={metric === 'units' ? 'active' : ''} onClick={() => setMetric('units')}>Порции</button><button className={metric === 'revenue' ? 'active' : ''} onClick={() => setMetric('revenue')}>Выручка</button></div></div>{!rows.length ? <Empty /> : <div className="dish-ranking">{(compact ? sorted.slice(0, 5) : sorted).map((d, index) => <div className="dish-row" key={d.dish_id}><span className="rank-number">{String(index + 1).padStart(2, '0')}</span><div className="dish-info"><div className="dish-label"><strong>{d.dish_name}</strong><span>{metric === 'units' ? n(d.units) : money(d.revenue)}</span></div><div className="rank-track"><div style={{ width: `${d[metric] / max * 100}%` }} /></div></div></div>)}</div>}</>;
}

function CustomersPage({ query, revision, retry }: { query: string; revision: number; retry: () => void }) {
  const customers = useJSON<{ rows: CustomerRow[] }>(`/api/customers?${query}`, revision);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState<'units' | 'orders' | 'revenue' | 'average_order'>('units');
  const [expanded, setExpanded] = useState<string | null>(null);
  if (customers.error) return <ErrorBox text={customers.error} retry={retry} />;
  if (!customers.data) return <Loading />;
  const rows = customers.data.rows;
  if (!rows.length) return <Panel title="Статистика клиентов"><Empty /></Panel>;
  const leaders = rows.filter(c => c.portion_rank === 1);
  const sorted = rows.filter(c => `${c.full_name} ${c.customer_id}`.toLocaleLowerCase('ru-RU').includes(search.trim().toLocaleLowerCase('ru-RU')))
    .sort((a, b) => b[sort] - a[sort] || a.customer_id.localeCompare(b.customer_id));
  const totalUnits = rows.reduce((sum, c) => sum + c.units, 0);
  return <div className={`customers-page ${customers.loading ? 'updating' : ''}`} aria-busy={customers.loading}>
    <section className="gourmet-award" aria-label="Медаль за количество порций">
      <div className="gourmet-medal"><Trophy size={34} strokeWidth={1.6} /><span>№ 1</span></div>
      <div className="gourmet-copy">
        <span className="gourmet-eyebrow">{leaders.length === 1 ? 'МЕДАЛЬ ЗА АППЕТИТ' : 'МЕДАЛИ ЗА АППЕТИТ'}</span>
        <h2>Главный гурман</h2>
        <p className="gourmet-names">{leaders.map(c => c.full_name).join(' · ')}</p>
        <p className="gourmet-description">{leaders.length === 1 ? 'Больше всего заказанных порций за выбранный период.' : 'Первое место разделили несколько клиентов с одинаковым числом порций.'}</p>
      </div>
      <div className="gourmet-score"><strong>{n(leaders[0].units)}</strong><span>{leaders.length > 1 ? 'порций у каждого' : 'порций заказано'}</span></div>
    </section>
    <div className="customer-summary">
      <span><Users size={16} /><strong>{n(rows.length)}</strong> клиентов с заказами</span>
      <span><UtensilsCrossed size={16} /><strong>{(totalUnits / rows.length).toLocaleString('ru-RU', { maximumFractionDigits: 1 })}</strong> порций на клиента</span>
      <span>Медаль пересчитывается при смене фильтров</span>
    </div>
    <Panel title="Кто сколько съел" subtitle="Заказанные порции, расходы и любимые блюда. Нажмите на имя, чтобы раскрыть состав заказов."
      action={<label className="search-input customer-search"><Search size={15} /><input aria-label="Поиск клиента" placeholder="Имя или ID клиента" value={search} onChange={e => setSearch(e.target.value)} />{search && <button aria-label="Очистить поиск клиента" onClick={() => setSearch('')}><X size={13} /></button>}</label>}>
      {!sorted.length ? <Empty title="Клиент не найден" text="Попробуйте другое имя или ID клиента." /> : <div className="table-scroll">
        <table className="data-table customer-table">
          <thead><tr><th>Клиент</th>{([['units', 'Порции'], ['orders', 'Заказы'], ['revenue', 'Потрачено'], ['average_order', 'Средний чек']] as [typeof sort, string][]).map(([key, title]) =>
            <th key={key} aria-sort={sort === key ? 'descending' : 'none'}><button className={sort === key ? 'sort-active' : ''} onClick={() => setSort(key)}>{title}{sort === key && <ChevronDown size={12} />}</button></th>
          )}<th>Любимое блюдо</th></tr></thead>
          <tbody>{sorted.map(c => <Fragment key={c.customer_id}>
            <tr className={c.portion_rank === 1 ? 'customer-winner' : ''}>
              <td><button className="customer-name" aria-expanded={expanded === c.customer_id} aria-controls={`dishes-${c.customer_id}`} onClick={() => setExpanded(expanded === c.customer_id ? null : c.customer_id)}>
                <span className={`customer-place ${c.portion_rank === 1 ? 'gold' : ''}`} title={c.portion_rank === 1 ? 'Главный гурман' : `Место по порциям: ${c.portion_rank}`}>{c.portion_rank === 1 ? <Trophy size={17} /> : c.portion_rank}</span>
                <span><strong>{c.full_name}</strong><small>{c.customer_id}</small></span><ChevronDown size={13} className={expanded === c.customer_id ? 'rotated' : ''} />
              </button></td>
              <td><strong className="customer-units">{n(c.units)}</strong></td><td>{n(c.orders)}</td><td className="emphasis">{money(c.revenue)}</td><td>{preciseRubles.format(c.average_order)}</td>
              <td><span className="customer-favorite">{c.dishes[0]?.dish_name}<small>{n(c.dishes[0]?.units || 0)} порций</small></span></td>
            </tr>
            {expanded === c.customer_id && <tr className="customer-details-row"><td colSpan={6}><div id={`dishes-${c.customer_id}`} className="customer-details">
              <div className="customer-details-heading"><strong>Что заказывал клиент</strong><span>Последний заказ: {day(c.last_order_date)} {c.last_order_date.slice(0, 4)}</span></div>
              <div className="customer-dishes">{c.dishes.map(d => <div key={d.dish_id}>
                <div><span>{d.dish_name}</span><strong>{n(d.units)} порций</strong></div>
                <div className="rank-track"><div style={{ width: `${d.units / c.dishes[0].units * 100}%` }} /></div>
              </div>)}</div>
            </div></td></tr>}
          </Fragment>)}</tbody>
        </table>
      </div>}
      <p className="customer-table-note">Любимое блюдо — первое по числу порций; при равенстве — по числу заказов, затем по ID блюда.</p>
    </Panel>
  </div>;
}

function QualityPage({ revision, retry }: { revision: number; retry: () => void }) {
  const quality = useJSON<Quality>('/api/quality', revision);
  const history = useJSON<{ rows: { correction_id: number; order_id: string; corrected_at: string; comment: string; run_id: number }[] }>('/api/corrections', revision);
  const [editing, setEditing] = useState<number | null>(null);
  const [success, setSuccess] = useState('');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [reason, setReason] = useState('');
  const [expanded, setExpanded] = useState<number | null>(null);
  useEffect(() => {
    if (search === query) return;
    const timer = setTimeout(() => { setQuery(search); setPage(1); }, 300);
    return () => clearTimeout(timer);
  }, [search, query]);
  const params = new URLSearchParams({ page: String(page), q: query });
  if (reason) params.set('reason', reason);
  const quarantine = useJSON<Quarantine>(`/api/quarantine?${params}`, revision);
  if (quality.error) return <ErrorBox text={quality.error} retry={retry} />;
  if (!quality.data) return <Loading />;
  const { summary, reasons, checks, profile } = quality.data;
  const reconciles = summary.unaccounted === 0 && summary.raw_rows === summary.loaded + summary.quarantined + summary.duplicates;
  const states = [{ key: 'loaded' as const, title: 'Загружено', color: '#547b49' }, { key: 'quarantined' as const, title: 'В карантине', color: '#dca35e' }, { key: 'duplicates' as const, title: 'Дубликаты', color: '#bbc5ba' }, { key: 'unaccounted' as const, title: 'Не учтено', color: '#c57667' }];
  return <div className="page-stack"><div className="scope-note"><Info size={16} />Здесь показаны все исходные записи. Фильтры периода и ресторана относятся к бизнес-аналитике.</div>
    {success && <div className="correction-success" role="status"><CircleCheck size={18} /><span>{success}</span><button className="icon-button" aria-label="Закрыть уведомление" onClick={() => setSuccess('')}><X size={15} /></button></div>}
    <Panel title="Каждая строка под контролем" subtitle={`${n(summary.raw_rows)} исходных записей · категории не пересекаются`} action={<span className="status-pill">{reconciles ? <CircleCheck size={14} /> : <Info size={14} />}{reconciles ? "Баланс сходится" : "Есть расхождения"}</span>}>
      <div className="processing-cards">{states.map(s => <div key={s.key}><span className="label-dot" style={{ background: s.color }} /><span>{s.title}</span><strong>{n(summary[s.key])}</strong><small>{(summary[s.key] / (summary.raw_rows || 1) * 100).toLocaleString('ru-RU', { maximumFractionDigits: 1 })}% исходных строк</small></div>)}</div>
      <div className="processing-bar">{states.filter(s => summary[s.key] > 0).map(s => <div key={s.key} style={{ width: `${summary[s.key] / summary.raw_rows * 100}%`, background: s.color }} title={`${s.title}: ${n(summary[s.key])}`} />)}</div>
    </Panel>
    <div className="quality-grid"><Panel title="Почему записи отклонены" subtitle="У одной строки может быть несколько причин"><div className="reasons-list">{reasons.map(r => <button key={r.reason} className={reason === r.reason ? 'reason-row selected' : 'reason-row'} onClick={() => { setReason(reason === r.reason ? '' : r.reason); setPage(1); }}><span>{r.description}</span><strong>{n(r.affected_raw_rows)}<ArrowRight size={14} /></strong></button>)}</div></Panel>
      <Panel title="Проверки качества" subtitle={`${checks.filter(c => c.passed).length} из ${checks.length} выполнены успешно`}><div className="checks-list">{checks.map(c => <div key={c.check_name}><span className={c.passed ? 'check-pass' : 'check-fail'}>{c.passed ? <Check size={14} /> : <X size={14} />}</span><span>{({ all_raw_accounted: 'Все исходные строки учтены', raw_multiset_unchanged: 'RAW сохранён без изменений', dispositions_are_disjoint: 'Категории не пересекаются', duplicate_lineage_valid: 'Дубликаты связаны с оригиналом', quarantine_original_and_reasons_saved: 'Причины и оригиналы сохранены', every_nonduplicate_prepared: 'Все уникальные записи обработаны', one_item_per_order: 'Состав заказа соответствует источнику', person_aliases_have_reference: 'Справочники согласованы', restaurant_mart_reconciles: 'Витрина ресторанов сходится', dish_mart_reconciles: 'Витрина блюд сходится', fulfillment_mart_reconciles: 'Витрина доставки сходится' } as Record<string, string>)[c.check_name] || c.check_name}</span></div>)}</div></Panel></div>
    <Panel title="Карантин" subtitle="Исходные значения сохранены. Нажмите на строку, чтобы увидеть запись целиком." action={<span className="count-tag">{n(quarantine.data?.total || 0)} записей</span>}>
      <div className="quarantine-toolbar"><label className="search-input"><Search size={16} /><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Заказ, имя или значение…" aria-label="Поиск по карантину" />{search && <button aria-label="Очистить поиск" onClick={() => setSearch('')}><X size={14} /></button>}</label><label className="select-wrap"><select aria-label="Причина карантина" value={reason} onChange={e => { setReason(e.target.value); setPage(1); }}><option value="">Все причины</option>{reasons.map(r => <option value={r.reason} key={r.reason}>{r.description}</option>)}</select><ChevronDown size={14} /></label></div>
      {quarantine.error ? <ErrorBox text={quarantine.error} retry={retry} /> : quarantine.loading ? <Loading /> : quarantine.data?.rows.length ? <><div className="quarantine-list">{quarantine.data.rows.map(row => <div className="quarantine-record" key={row.raw_id}><button className="quarantine-record-head" aria-expanded={expanded === row.raw_id} onClick={() => setExpanded(expanded === row.raw_id ? null : row.raw_id)}><span className="raw-number">#{row.raw_id}</span><strong>{row.source_record.order_id || 'Без номера'}</strong><span className="raw-customer">{row.source_record.customer_info || 'Клиент не указан'}</span><span className="reason-count">{row.reasons.length} {row.reasons.length === 1 ? 'причина' : 'причины'}</span><ChevronDown size={16} className={expanded === row.raw_id ? 'rotated' : ''} /></button>{expanded === row.raw_id && <div className="record-details"><dl>{Object.entries(row.source_record).map(([key, value]) => <div key={key}><dt>{key}</dt><dd>{value || <span className="muted">Пустое значение</span>}</dd></div>)}</dl><ul>{row.reasons.map(code => <li key={code}>{reasons.find(r => r.reason === code)?.description || code}</li>)}</ul>{editing === row.raw_id ? <QuarantineEditor rawId={row.raw_id} onClose={() => setEditing(null)} onSaved={orderId => { setEditing(null); setExpanded(null); setPage(1); setReason(''); setSearch(''); setQuery(''); setSuccess(`Заказ ${orderId} выведен из карантина. Аналитика обновлена.`); retry(); }} /> : <button type="button" className="button button-dark correction-open" onClick={() => { setEditing(row.raw_id); setSuccess(''); }}>Исправить запись</button>}</div>}</div>)}</div><div className="pagination"><span>Страница {page} из {Math.max(1, Math.ceil(quarantine.data.total / quarantine.data.page_size))}</span><div><button className="icon-button" aria-label="Предыдущая страница" disabled={page === 1} onClick={() => setPage(p => p - 1)}><ChevronLeft size={17} /></button><button className="icon-button" aria-label="Следующая страница" disabled={page * quarantine.data.page_size >= quarantine.data.total} onClick={() => setPage(p => p + 1)}><ChevronRight size={17} /></button></div></div></> : <Empty title="Записи не найдены" text="Измените поисковый запрос или выбранную причину." />}
    </Panel>
    {history.data?.rows.length ? <Panel title="Последние исправления" subtitle="Исходные записи сохранены. Исправления применяются при последующих загрузках."><div className="correction-history">{history.data.rows.map(row => <article key={row.correction_id}><div><strong>{row.order_id}</strong><span>{timestamp(row.corrected_at)} · загрузка #{row.run_id}</span></div>{row.comment && <p>{row.comment}</p>}</article>)}</div></Panel> : null}
    <Panel title="Профиль исходных столбцов" subtitle="Пустые строки и текстовые маркеры учитываются отдельно"><div className="table-scroll"><table className="data-table"><thead><tr><th>Столбец</th><th>Строк</th><th>Пустые</th><th>Маркеры пропусков</th><th>Различных значений</th></tr></thead><tbody>{profile.map(p => <tr key={p.column_name}><td className="code-cell">{p.column_name}</td><td>{n(p.raw_rows)}</td><td>{n(p.empty_rows)}</td><td>{n(p.placeholder_rows)}</td><td>{n(p.distinct_values)}</td></tr>)}</tbody></table></div></Panel>
  </div>;
}

function RunsPage({ revision, retry }: { revision: number; retry: () => void }) {
  const { data, error } = useJSON<{ rows: Run[] }>('/api/runs', revision);
  if (error) return <ErrorBox text={error} retry={retry} />;
  if (!data) return <Loading />;
  return <Panel title="История загрузок" subtitle="Контрольные суммы сравнивают бизнес-строки, исходы обработки и витрины между запусками.">
    {!data.rows.length ? <Empty title="Загрузок пока нет" text="История появится после выполнения pipeline." /> : <div className="runs-list">{data.rows.map(run => <article className="run-card" key={run.run_id}><div className="run-icon"><GitBranch size={21} /></div><div className="run-main"><div className="run-title"><h3>Загрузка #{run.run_id}</h3><span className="status-pill"><Check size={12} />{run.metrics.quality_checks_passed ? 'Проверки пройдены' : 'Требует проверки'}</span></div><p>{timestamp(run.finished_at)} <span>·</span> {Number(run.duration_seconds).toLocaleString('ru-RU', { maximumFractionDigits: 2 })} сек.</p><div className="run-stats"><span><strong>{n(run.metrics.loaded)}</strong> загружено</span><span><strong>{n(run.metrics.quarantined)}</strong> в карантине</span><span><strong>{n(run.metrics.duplicates)}</strong> дублей</span><span><strong>{money(run.metrics.total_amount)}</strong> сумма заказов</span></div>{run.previous_run_id && <div className={`run-comparison ${run.all_metrics_equal ? '' : 'changed'}`}><Layers size={14} />{run.all_metrics_equal ? `Результат полностью совпадает с загрузкой #${run.previous_run_id}` : `Результат отличается от загрузки #${run.previous_run_id}`}</div>}</div></article>)}</div>}
  </Panel>;
}

export default function App() {
  const [tab, setTab] = useState<Tab>('overview');
  const [revision, setRevision] = useState(0);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [start, setStart] = useState(() => cachedJSON<Bootstrap>('/api/bootstrap')?.bounds.start || '');
  const [end, setEnd] = useState(() => cachedJSON<Bootstrap>('/api/bootstrap')?.bounds.end || '');
  const [restaurant, setRestaurant] = useState('');
  const [chartRestaurants, setChartRestaurants] = useState<string[]>([]);
  const [preset, setPreset] = useState('all');
  const [metric, setMetric] = useState<Metric>('revenue');
  const [grain, setGrain] = useState<Grain>('week');
  const bootstrap = useJSON<Bootstrap>('/api/bootstrap', revision);
  useEffect(() => {
    const bounds = bootstrap.data?.bounds;
    if (preset !== 'custom' && bounds?.start && bounds.end) {
      setStart(preset === 'all' ? bounds.start : [bounds.start, dateShift(bounds.end, 1 - Number(preset))].sort()[1]);
      setEnd(bounds.end);
    }
  }, [bootstrap.data, preset]);
  const filterError = start && end ? (start > end ? 'Начало периода должно быть не позже окончания.' : '') : (start || end) ? 'Укажите обе даты периода.' : '';
  const params = new URLSearchParams({ start, end, granularity: grain });
  if (restaurant) params.set('restaurant', restaurant);
  const dashboard = useJSON<Dashboard>(start && end && !filterError ? `/api/dashboard?${params}` : null, revision);
  const refresh = () => setRevision(value => value + 1);
  const changeTab = (value: Tab) => { setTab(value); setSidebarOpen(false); window.scrollTo({ top: 0, behavior: 'instant' }); };
  const selectRestaurant = (id: string) => { setRestaurant(id); changeTab('overview'); };
  const analytics = ['overview', 'restaurants', 'dishes', 'customers'].includes(tab);
  const activeTab = tabs.find(t => t.key === tab)!;
  const pageTitles: Record<Tab, [string, string]> = {
    overview: ['Бизнес в деталях', 'Всё, что нужно знать о ваших заказах. В одном месте.'],
    restaurants: ['Рестораны', 'Сравнивайте заведения и находите точки роста.'],
    dishes: ['Что выбирают гости', 'Популярность блюд в заказах за выбранный период.'],
    customers: ['Аппетит в цифрах', 'Кто сколько заказал, что любит и кому достанется медаль.'],
    quality: ['Данным можно доверять', 'Прозрачная обработка каждой исходной записи.'],
    runs: ['Каждая загрузка — на виду', 'Результаты pipeline и проверка воспроизводимости.'],
  };
  const setPeriod = (value: string) => { setPreset(value); if (!bootstrap.data?.bounds.end || !bootstrap.data.bounds.start) return; const max = bootstrap.data.bounds.end; setEnd(max); setStart(value === 'all' ? bootstrap.data.bounds.start : [bootstrap.data.bounds.start, dateShift(max, 1 - Number(value))].sort()[1]); };
  const data = dashboard.data;
  return <div className="app-shell">
    {sidebarOpen && <button className="sidebar-overlay" aria-label="Закрыть меню" onClick={() => setSidebarOpen(false)} />}
    <aside className={`sidebar ${sidebarOpen ? 'open' : ''}`}><a className="brand" href="#" onClick={e => { e.preventDefault(); changeTab('overview'); }}><span className="brand-symbol"><ChartNoAxesCombined size={25} strokeWidth={2.6} /></span><span>срез<span className="brand-dot">.</span></span></a><div className="workspace"><span className="workspace-icon"><UtensilsCrossed size={17} /></span><div><strong>Доставка еды</strong><small>Рабочее пространство</small></div><span className="workspace-number">02</span></div><div className="nav-caption">АНАЛИТИКА</div><nav aria-label="Основная навигация">{tabs.map(t => <button key={t.key} className={`nav-item ${tab === t.key ? 'active' : ''}`} onClick={() => changeTab(t.key)} aria-current={tab === t.key ? 'page' : undefined}><t.icon size={18} /><span>{t.name}</span>{t.key === 'quality' && bootstrap.data && <small>{n(bootstrap.data.processing.quarantined)}</small>}</button>)}</nav>
      <div className="sidebar-bottom"><a href="/er.jpg" target="_blank" rel="noreferrer" className="schema-link"><Layers size={17} />Схема данных<ExternalLink size={13} /></a><div className="data-source"><div><span className={`live-dot ${bootstrap.error ? 'offline' : ''}`} /><strong>{bootstrap.data && !bootstrap.error ? 'Источник подключён' : bootstrap.error ? 'Источник недоступен' : 'Подключаем источник'}</strong></div><p>PostgreSQL · practice_02</p>{bootstrap.data?.latest_run && <small>Загрузка от {timestamp(bootstrap.data.latest_run.finished_at)}</small>}</div><div className="user"><span className="user-avatar">02</span><div><strong>Команда 02</strong><small>Аналитика доставки</small></div><span className="user-role">DW</span></div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div className="breadcrumb"><button className="mobile-menu icon-button" aria-label="Открыть меню" onClick={() => setSidebarOpen(true)}><Menu size={19} /></button><span>Рабочее пространство</span><ChevronRight size={13} /><strong>{activeTab.name}</strong></div><span className="topbar-tag"><span className="tiny-dot" />Команда 02</span></header>
      <main><div className="page-heading"><div><div className="eyebrow">АНАЛИТИКА ДОСТАВКИ</div><h1>{pageTitles[tab][0]}</h1><p>{pageTitles[tab][1]}</p></div><div className="heading-actions"><button className={`icon-button refresh-button ${dashboard.loading || bootstrap.loading ? 'is-loading' : ''}`} aria-label="Обновить данные" title="Обновить данные" onClick={refresh}><RefreshCw size={17} /></button>{analytics && <a className={`button button-dark ${!start || !end || filterError || dashboard.loading || dashboard.error ? 'disabled' : ''}`} href={`/api/export.csv?${params}`} aria-disabled={!start || !end || !!filterError || dashboard.loading || !!dashboard.error} onClick={e => { if (!start || !end || filterError || dashboard.loading || dashboard.error) e.preventDefault(); }} download><Download size={16} />Экспорт CSV</a>}</div></div>
      {bootstrap.error && <ErrorBox text={bootstrap.error} retry={refresh} />}
      {analytics && bootstrap.data && <><section className="filter-bar" aria-label="Фильтры аналитики"><div className="date-range"><CalendarDays size={16} /><input type="date" aria-label="Начало периода" value={start} onChange={e => { setStart(e.target.value); setPreset('custom'); }} /><span>—</span><input type="date" aria-label="Конец периода" value={end} onChange={e => { setEnd(e.target.value); setPreset('custom'); }} /></div><label className="select-wrap restaurant-filter"><Store size={15} /><select aria-label="Ресторан" value={restaurant} onChange={e => setRestaurant(e.target.value)}><option value="">Все рестораны</option>{bootstrap.data.restaurants.map(r => <option key={r.restaurant_id} value={r.restaurant_id}>{r.restaurant_name}</option>)}</select><ChevronDown size={14} /></label><div className="period-presets">{[['all', 'Весь период'], ['90', '90 дней'], ['30', '30 дней']].map(([key, label]) => <button className={preset === key ? 'active' : ''} onClick={() => setPeriod(key)} key={key}>{label}</button>)}</div></section><div className="filter-caption"><span><span className="tiny-dot" />Только корректно загруженные заказы</span><span>{dashboard.loading ? 'Обновляем данные…' : data ? `Обновлено в ${new Date(data.fetched_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' })}` : ''}</span></div></>}
      {analytics && filterError && <div className="error-box" role="alert"><Info size={18} />{filterError}</div>}
      {analytics && dashboard.error && <ErrorBox text={dashboard.error} retry={refresh} />}
      {analytics && !data && !dashboard.error && !bootstrap.error && <Loading />}
      {analytics && data && !filterError && !dashboard.error && <div className={`analytics-content ${dashboard.loading ? 'updating' : ''}`} aria-busy={dashboard.loading}><div className="stats-grid"><Stat index={0} label="Выручка" value={data.summary.revenue} previous={data.previous.revenue} icon={<Wallet size={17} />} /><Stat index={1} label="Заказы" value={data.summary.orders} previous={data.previous.orders} icon={<ShoppingBag size={17} />} /><Stat index={2} label="Средний чек" value={data.summary.average_order} previous={data.previous.average_order} icon={<TrendingUp size={17} />} /><Stat index={3} label="Блюд заказано" value={data.summary.units} previous={data.previous.units} icon={<UtensilsCrossed size={17} />} /></div>
      {tab === 'overview' && <><div className="charts-grid"><Panel title="Динамика заказов" subtitle={start && end ? `${day(start)} — ${day(end)} ${end.slice(0, 4)}` : ''} className="trend-panel" action={<div className="segmented"><button className={metric === 'revenue' ? 'active' : ''} onClick={() => setMetric('revenue')}>Выручка</button><button className={metric === 'orders' ? 'active' : ''} onClick={() => setMetric('orders')}>Заказы</button></div>}><div className="chart-topline"><div><span className="chart-legend-dot" />{metric === 'revenue' ? 'Выручка, ₽' : 'Количество заказов'}</div><select value={grain} onChange={e => setGrain(e.target.value as Grain)} aria-label="Группировка графика"><option value="day">По дням</option><option value="week">По неделям</option><option value="month">По месяцам</option></select></div>{!data.summary.orders ? <Empty /> : <div className="trend-chart" role="img" aria-label={`Динамика ${metric === 'revenue' ? 'выручки' : 'заказов'} за выбранный период`}><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.trend} margin={{ top: 16, right: 12, bottom: 0, left: -15 }}><defs><linearGradient id="revenue-gradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#bedb9c" stopOpacity={0.5} /><stop offset="100%" stopColor="#bedb9c" stopOpacity={0.025} /></linearGradient></defs><CartesianGrid strokeDasharray="3 5" vertical={false} stroke="#e9ede7" /><XAxis dataKey="date" tickFormatter={day} axisLine={false} tickLine={false} tick={{ fill: '#93988f', fontSize: 11 }} minTickGap={38} dy={10} /><YAxis tickFormatter={value => short(Number(value))} tick={{ fill: '#93988f', fontSize: 11 }} axisLine={false} tickLine={false} width={72} tickCount={5} /><Tooltip cursor={{ stroke: '#89a47c', strokeDasharray: '4 4' }} content={({ active, payload, label }) => active && payload?.length ? <div className="chart-tooltip"><span>{day(String(label))}</span><strong>{metric === 'revenue' ? money(Number(payload[0].value)) : `${n(Number(payload[0].value))} заказов`}</strong></div> : null} /><Area type="monotone" dataKey={metric} stroke="#4f7541" fill="url(#revenue-gradient)" strokeWidth={2.5} isAnimationActive={false} activeDot={{ r: 5, fill: '#315c48', stroke: 'white', strokeWidth: 3 }} /></AreaChart></ResponsiveContainer></div>}</Panel>
        <Panel title="Как получают заказы" subtitle="Способ получения" className="fulfillment-panel">{!data.summary.orders ? <Empty /> : <><div className="donut-container"><ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={fulfillment.map(f => ({ ...f, orders: data.fulfillment.find(row => row.type === f.key)?.orders || 0 }))} dataKey="orders" nameKey="name" innerRadius="65%" outerRadius="86%" paddingAngle={3} cornerRadius={3} stroke="none" startAngle={90} endAngle={-270} isAnimationActive={false}>{fulfillment.map(f => <Cell key={f.key} fill={f.color} />)}</Pie><Tooltip formatter={(value) => `${n(Number(value))} заказов`} contentStyle={{ borderRadius: 12, borderColor: '#e6e9e3', fontSize: 12 }} /></PieChart></ResponsiveContainer><div className="donut-center"><strong>{n(data.summary.orders)}</strong><span>всего заказов</span></div></div><div className="fulfillment-legend">{fulfillment.map(f => { const count = data.fulfillment.find(row => row.type === f.key)?.orders || 0; return <div key={f.key}><span className="label-dot" style={{ background: f.color }} /><span>{f.name}</span><strong>{(count / data.summary.orders * 100).toLocaleString('ru-RU', { maximumFractionDigits: 1 })}%</strong></div>; })}</div></>}</Panel></div>
        <div className="bottom-grid"><Panel title="Рестораны" subtitle="Кто приносит больше выручки" action={<button className="text-button" onClick={() => changeTab('restaurants')}>Все рестораны<ArrowRight size={14} /></button>}><RestaurantTable rows={data.restaurants} onSelect={selectRestaurant} compact /></Panel><Panel title="В любимчиках у гостей" subtitle="Популярные блюда" action={<button className="small-arrow" aria-label="Все блюда" onClick={() => changeTab('dishes')}><ArrowUpRight size={18} /></button>}><DishRanking rows={data.dishes} compact /></Panel></div></>}
      {tab === 'restaurants' && <div className="page-stack"><OrderTimeDistribution restaurants={bootstrap.data?.restaurants || []} selected={chartRestaurants} onSelect={setChartRestaurants} start={start} end={end} revision={revision} retry={refresh} /><Panel title="Показатели ресторанов" subtitle="Нажмите на заголовок, чтобы изменить сортировку." action={<span className="count-tag">{data.restaurants.length} заведений</span>}><RestaurantTable rows={data.restaurants} onSelect={setRestaurant} /></Panel></div>}
      {tab === 'dishes' && <div className="dish-page-grid"><Panel title="Рейтинг блюд" subtitle="Один заказ в источнике содержит одно блюдо"><DishRanking rows={data.dishes} /></Panel><Panel title="Блюда в цифрах" subtitle="Выручка относится к заказам с этим блюдом"><div className="table-scroll"><table className="data-table"><thead><tr><th>Блюдо</th><th>Цена за порцию</th><th>Заказы</th><th>Порции</th><th>Выручка</th></tr></thead><tbody>{data.dishes.map(d => <tr key={d.dish_id}><td><strong>{d.dish_name}</strong></td><td>{d.unit_price == null ? 'Не определена' : preciseRubles.format(d.unit_price)}</td><td>{n(d.orders)}</td><td>{n(d.units)}</td><td className="emphasis">{money(d.revenue)}</td></tr>)}</tbody></table>{!data.dishes.length && <Empty />}</div></Panel></div>}
      {tab === 'customers' && <CustomersPage query={params.toString()} revision={revision} retry={refresh} />}
      <div className="analytics-note"><ShieldCheck size={15} /><span>В аналитике учтены только загруженные заказы. Отклонённые записи доступны в разделе <button onClick={() => changeTab('quality')}>«Качество данных»</button>.</span></div></div>}
      {tab === 'quality' && <QualityPage revision={revision} retry={refresh} />}
      {tab === 'runs' && <RunsPage revision={revision} retry={refresh} />}
      <footer><span>срез<span className="footer-dot">.</span> <span className="footer-divider">/</span> Аналитика доставки</span><span>Доставка еды · Команда 02</span></footer>
      </main></div>
  </div>;
}
