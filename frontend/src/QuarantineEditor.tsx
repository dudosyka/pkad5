import { useEffect, useState } from 'react';
import type { FormEvent, ReactNode } from 'react';
import { Info, RefreshCw, Save, X } from 'lucide-react';

type Values = {
  order_id: string; ordered_at: string; customer_id: string; restaurant_id: string;
  dish_id: string; quantity: string; total_amount: string; fulfillment_type: string;
  courier_id: string; phone_extension: string; comment: string;
};
type Detail = {
  source_record: Record<string, string | null>; expected_correction_id: number | null;
  values: Record<keyof Values, string | number | null>;
  issues: { code: string; field: keyof Values; message: string }[];
};
type Options = {
  customers: { customer_id: string; full_name: string; phone: string | null }[];
  couriers: { courier_id: string; full_name: string }[];
  restaurants: { restaurant_id: string; restaurant_name: string; city: string }[];
  dishes: { dish_id: string; dish_name: string }[];
};
const empty: Values = { order_id: '', ordered_at: '', customer_id: '', restaurant_id: '', dish_id: '', quantity: '', total_amount: '', fulfillment_type: '', courier_id: '', phone_extension: '', comment: '' };

export default function QuarantineEditor({ rawId, onClose, onSaved }: { rawId: number; onClose: () => void; onSaved: (orderId: string) => void }) {
  const [detail, setDetail] = useState<Detail | null>(null);
  const [options, setOptions] = useState<Options | null>(null);
  const [values, setValues] = useState<Values>(empty);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setError(''); setDetail(null); setOptions(null);
    const get = async (url: string) => {
      const response = await fetch(url, { signal: controller.signal });
      const body = await response.json();
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Не удалось открыть запись.');
      return body;
    };
    Promise.all([get(`/api/quarantine/${rawId}`), get('/api/correction-options')]).then(([row, refs]: [Detail, Options]) => {
      if (controller.signal.aborted) return;
      const fields = { ...empty };
      for (const key of Object.keys(fields) as (keyof Values)[]) fields[key] = row.values[key] == null ? '' : String(row.values[key]);
      if (fields.fulfillment_type === 'delivery' && !fields.courier_id && !row.issues.some(issue => issue.field === 'courier_id')) fields.courier_id = '_unassigned';
      setDetail(row); setOptions(refs); setValues(fields);
      setErrors(Object.fromEntries(row.issues.filter(issue => issue.field).map(issue => [issue.field, issue.message])));
    }).catch(e => { if (!controller.signal.aborted) setError(e instanceof Error ? e.message : 'Не удалось открыть запись.'); });
    return () => controller.abort();
  }, [rawId, revision]);

  const change = (field: keyof Values, value: string) => {
    setValues(current => ({ ...current, [field]: value, ...(field === 'fulfillment_type' ? { courier_id: '' } : {}) }));
    setErrors(current => ({ ...current, [field]: '', ...(field === 'fulfillment_type' ? { courier_id: '' } : {}) }));
  };
  const field = (key: keyof Values, label: string, input: ReactNode, hint?: string) => <div className={`correction-field ${errors[key] ? 'has-error' : ''}`}>
    <label htmlFor={`correct-${rawId}-${key}`}>{label}</label>{input}
    {(errors[key] || hint) && <small id={`hint-${rawId}-${key}`}>{errors[key] || hint}</small>}
  </div>;
  const attrs = (key: keyof Values) => ({ id: `correct-${rawId}-${key}`, value: values[key], 'aria-invalid': !!errors[key], 'aria-describedby': `hint-${rawId}-${key}`, onChange: (e: { target: { value: string } }) => change(key, e.target.value) });
  async function save(event: FormEvent) {
    event.preventDefault();
    if (!detail || saving) return;
    setSaving(true); setError(''); setErrors({});
    try {
      const response = await fetch(`/api/quarantine/${rawId}/correct`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...values, quantity: Number(values.quantity), courier_id: values.fulfillment_type === 'delivery' && values.courier_id !== '_unassigned' ? values.courier_id || null : null,
          phone_extension: values.phone_extension || null, source_record: detail.source_record, expected_correction_id: detail.expected_correction_id }),
      });
      const result = await response.json();
      if (!response.ok) {
        const problem = result.detail;
        if (Array.isArray(problem)) setErrors(Object.fromEntries(problem.map(item => [item.loc[item.loc.length - 1], 'Проверьте значение: поле обязательно и должно соответствовать формату.'])));
        else if (problem?.fields) setErrors(problem.fields);
        setError(typeof problem === 'string' ? problem : problem?.message || 'Проверьте заполненные поля. Исправления не сохранены.');
        return;
      }
      onSaved(result.order_id);
    } catch {
      setError('Не удалось получить результат. Обновите карантин перед повторной отправкой: исправление могло сохраниться.');
    } finally { setSaving(false); }
  }
  return <section className="correction-editor" aria-label={`Исправление записи ${rawId}`}>
    <div className="correction-heading"><div><h3>Исправить и загрузить</h3><p>Уточните выделенные поля. Известные значения уже заполнены.</p></div><button type="button" className="icon-button" aria-label="Закрыть исправление" disabled={saving} onClick={onClose}><X size={16} /></button></div>
    {error && <div className="error-box" role="alert"><Info size={18} /><span>{error}</span>{!detail && <button type="button" onClick={() => setRevision(v => v + 1)}>Повторить</button>}</div>}
    {!detail || !options ? !error && <div className="loading-state" role="status"><RefreshCw className="spin" size={20} />Открываем запись…</div> : <form onSubmit={save}>
      <fieldset disabled={saving} className="correction-fields">
        {field('order_id', 'Номер заказа', <input {...attrs('order_id')} required maxLength={80} placeholder="FD-50001" />, 'Укажите подтверждённый уникальный номер заказа.')}
        {field('ordered_at', 'Дата и время заказа', <input {...attrs('ordered_at')} type="datetime-local" required step="1" />)}
        {field('customer_id', 'Клиент', <select {...attrs('customer_id')} required><option value="">Выберите клиента</option>{options.customers.map(c => <option key={c.customer_id} value={c.customer_id}>{c.full_name} · {c.customer_id}{c.phone ? ` · ${c.phone}` : ''}</option>)}</select>, 'ФИО и телефон берутся из выбранной записи справочника.')}
        {field('phone_extension', 'Добавочный номер', <input {...attrs('phone_extension')} inputMode="numeric" pattern="[0-9]{1,12}" maxLength={12} placeholder="Не указан" />)}
        {field('restaurant_id', 'Ресторан', <select {...attrs('restaurant_id')} required><option value="">Выберите ресторан</option>{options.restaurants.map(r => <option key={r.restaurant_id} value={r.restaurant_id}>{r.restaurant_name} · {r.city}</option>)}</select>)}
        {field('dish_id', 'Блюдо', <select {...attrs('dish_id')} required><option value="">Выберите блюдо</option>{options.dishes.map(d => <option key={d.dish_id} value={d.dish_id}>{d.dish_name}</option>)}</select>)}
        {field('quantity', 'Количество порций', <input {...attrs('quantity')} type="number" min="1" max="999999999" step="1" required placeholder="Введите количество" />)}
        {field('total_amount', 'Сумма заказа, ₽', <input {...attrs('total_amount')} type="number" min="0.01" max="999999999999.99" step="0.01" required placeholder="Введите точную сумму" />)}
        {field('fulfillment_type', 'Способ получения', <select {...attrs('fulfillment_type')} required><option value="">Выберите способ</option><option value="pickup">Самовывоз</option><option value="delivery">Доставка</option><option value="unknown">Способ не указан</option></select>)}
        {values.fulfillment_type === 'delivery' && field('courier_id', 'Курьер', <select {...attrs('courier_id')} required><option value="">Уточните курьера</option><option value="_unassigned">Курьер не назначен</option>{options.couriers.map(c => <option key={c.courier_id} value={c.courier_id}>{c.full_name} · {c.courier_id}</option>)}</select>)}
        <div className="correction-comment">{field('comment', 'Комментарий к исправлению', <input {...attrs('comment')} maxLength={500} placeholder="Откуда получены уточнённые данные — необязательно" />)}</div>
      </fieldset>
      <p className="correction-note">Оригинал сохранится. Исправление попадёт в журнал, а заказ — в аналитику после успешной проверки. При ошибке изменения не сохраняются.</p>
      <div className="correction-actions"><button className="button button-dark" type="submit" disabled={saving}>{saving ? <RefreshCw size={16} className="spin" /> : <Save size={16} />}{saving ? 'Проверяем и загружаем…' : 'Сохранить и вывести из карантина'}</button><button type="button" className="button" disabled={saving} onClick={onClose}>Отмена</button></div>
      {saving && <p className="correction-note" role="status">Обновляем аналитику. Это может занять до полутора минут.</p>}
    </form>}
  </section>;
}
