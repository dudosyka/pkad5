import json
import os
from pathlib import Path
from urllib.request import urlopen

from playwright.sync_api import sync_playwright, expect

BASE = os.environ['BASE_URL']
if BASE != 'http://frontend' or os.environ.get('ALLOW_TEST_WRITES') != 'isolated-copy':
    raise RuntimeError('This check requires the isolated frontend and ALLOW_TEST_WRITES=isolated-copy.')

Path('/artifacts').mkdir(exist_ok=True)
with urlopen(BASE + '/api/quarantine?reason=dish_quantity_missing_or_invalid&page_size=1', timeout=30) as response:
    original = json.load(response)['rows'][0]
with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    page = browser.new_page(viewport={'width': 1440, 'height': 1050}, locale='ru-RU')
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(BASE, wait_until='networkidle')
    original_etag = page.evaluate("JSON.parse(localStorage.getItem('srez-api-cache')).entries.find(([url]) => url.startsWith('/api/dashboard?'))[1].etag")
    page.get_by_role('navigation').get_by_role('button', name='Качество данных').click()
    page.get_by_label('Причина карантина', exact=True).select_option('dish_quantity_missing_or_invalid')
    head = page.locator('.quarantine-record-head').first
    expect(head.locator('.raw-number')).to_have_text(f"#{original['raw_id']}")
    head.click()
    page.get_by_role('button', name='Исправить запись', exact=True).click()
    quantity = page.get_by_label('Количество порций', exact=True)
    expect(quantity).to_be_visible()
    expect(quantity).to_have_value('')
    expect(quantity).to_have_attribute('aria-invalid', 'true')
    page.locator('.correction-editor').scroll_into_view_if_needed()
    page.locator('.correction-editor').screenshot(path='/artifacts/correction-desktop.png', animations='disabled')
    page.set_viewport_size({'width': 390, 'height': 844})
    assert page.evaluate('document.documentElement.scrollWidth') <= 390
    page.locator('.correction-editor').screenshot(path='/artifacts/correction-mobile.png', animations='disabled')
    page.get_by_label('Номер заказа', exact=True).fill('FD-990000002')
    page.get_by_label('Дата и время заказа', exact=True).fill('2026-06-02T13:15')
    page.get_by_label('Клиент', exact=True).select_option('U001')
    page.get_by_label('Ресторан', exact=True).select_option('R1')
    page.get_by_label('Блюдо', exact=True).select_option('D1')
    quantity.fill('3')
    page.get_by_label('Сумма заказа, ₽', exact=True).fill('1500.50')
    page.get_by_label('Способ получения', exact=True).select_option('pickup')
    page.get_by_label('Комментарий к исправлению', exact=True).fill('Проверка формы на копии базы')
    with page.expect_response(lambda response: '/api/dashboard?' in response.url and response.status == 200, timeout=120000) as updated:
        page.get_by_role('button', name='Сохранить и вывести из карантина', exact=True).click()
    assert updated.value.headers['etag'] != original_etag
    expected_orders = updated.value.json()['summary']['orders']
    expect(page.get_by_text('Заказ FD-990000002 выведен из карантина. Аналитика обновлена.', exact=True)).to_be_visible(timeout=120000)
    expect(page.get_by_role('heading', name='Последние исправления', exact=True)).to_be_visible()
    expect(page.locator('.correction-history')).to_contain_text('FD-990000002')
    page.get_by_label('Поиск по карантину', exact=True).fill('FD-990000002')
    expect(page.get_by_text('Записи не найдены', exact=True)).to_be_visible(timeout=30000)
    page.set_viewport_size({'width': 1440, 'height': 1050})
    page.get_by_role('navigation').get_by_role('button', name='Обзор', exact=True).click()
    formatted_orders = page.evaluate("value => new Intl.NumberFormat('ru-RU').format(value)", expected_orders)
    expect(page.locator('.stat-value').nth(1)).to_have_text(formatted_orders)
    assert not errors, errors
    browser.close()
print('Correction form: missing values, mobile layout, save, history and removal from quarantine passed.')
