import csv
from collections import Counter, defaultdict
from datetime import datetime
import io
import json
import os
from pathlib import Path
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen

from playwright.sync_api import sync_playwright, expect

BASE = os.environ.get("BASE_URL", "http://frontend")


def get(path):
    with urlopen(BASE + path, timeout=30) as response:
        return json.load(response)


class API(unittest.TestCase):
    def test_restaurant_order_distribution(self):
        for query in ("", "?restaurant=R1&start=2026-06-01&end=2026-06-23", "?start=2026-01-06&end=2026-01-06", "?start=2025-01-01&end=2025-01-31"):
            with self.subTest(query=query):
                dashboard = get("/api/dashboard" + query)
                rows = dashboard["orders_by_hour"]
                self.assertEqual(get("/api/orders-by-hour" + query)["rows"], rows)
                self.assertEqual([row["hour"] for row in rows], list(range(24)))
                self.assertEqual(sum(row["orders"] for row in rows), dashboard["summary"]["orders"])
                with urlopen(BASE + "/api/export.csv" + query, timeout=30) as response:
                    orders = csv.DictReader(io.StringIO(response.read().decode("utf-8-sig")), delimiter=";")
                    expected = Counter(datetime.fromisoformat(order["Дата и время"]).hour for order in orders)
                self.assertEqual([row["orders"] for row in rows], [expected[hour] for hour in range(24)])

    def test_hourly_restaurant_multiselect(self):
        ids = [row["restaurant_id"] for row in get("/api/bootstrap")["restaurants"][:3]]
        self.assertGreaterEqual(len(ids), 2)
        for dates in ("", "&start=2026-06-01&end=2026-06-23", "&start=2025-01-01&end=2025-01-31"):
            singles = {id: get("/api/orders-by-hour?restaurant=" + id + dates)["rows"] for id in ids}
            for selected in (ids[:2], [ids[2], ids[1]] if len(ids) > 2 else [ids[1]]):
                with self.subTest(dates=dates, selected=selected):
                    path = "/api/orders-by-hour?" + "&".join("restaurant=" + id for id in selected) + dates
                    rows = get(path)["rows"]
                    self.assertEqual([row["hour"] for row in rows], list(range(24)))
                    self.assertEqual([row["orders"] for row in rows], [sum(singles[id][hour]["orders"] for id in selected) for hour in range(24)])
                    self.assertEqual(get(path + "&restaurant=" + selected[0])["rows"], rows)
        for query, status in (("restaurant=R1&restaurant=R999", 404), ("restaurant=R1&restaurant=R2%27", 422), ("restaurant=", 422), ("start=2026-06-23&end=2026-06-01", 422)):
            with self.assertRaises(HTTPError) as error:
                get("/api/orders-by-hour?" + query)
            self.assertEqual(error.exception.code, status)

    def test_schema_file(self):
        for path in ("/er.jpg", "/api/schema.svg"):
            with self.subTest(path=path), urlopen(BASE + path, timeout=30) as response:
                self.assertEqual(response.headers.get_content_type(), "image/jpeg")
                self.assertTrue(response.geturl().endswith("/er.jpg"))
                content = response.read()
                self.assertTrue(content.startswith(b"\xff\xd8\xff"))
                self.assertTrue(content.endswith(b"\xff\xd9"))

    def test_customer_totals_favorites_ranks_and_filters(self):
        for query in ["", "?restaurant=R1&start=2026-06-01&end=2026-06-23", "?start=2026-01-06&end=2026-01-06"]:
            with self.subTest(query=query):
                rows = get("/api/customers" + query)["rows"]
                summary = get("/api/dashboard" + query)["summary"]
                self.assertEqual(sum(c["orders"] for c in rows), summary["orders"])
                self.assertEqual(sum(c["units"] for c in rows), summary["units"])
                self.assertAlmostEqual(sum(c["revenue"] for c in rows), summary["revenue"])
                ranks = sorted({c["units"] for c in rows}, reverse=True)
                with urlopen(BASE + "/api/export.csv" + query, timeout=30) as response:
                    orders = list(csv.DictReader(io.StringIO(response.read().decode("utf-8-sig")), delimiter=";"))
                by_customer = defaultdict(list)
                for order in orders:
                    by_customer[order["Клиент"]].append(order)
                for customer in rows:
                    source = by_customer[customer["full_name"]]
                    self.assertEqual(customer["orders"], len(source))
                    self.assertEqual(customer["units"], sum(int(o["Количество"]) for o in source))
                    self.assertAlmostEqual(customer["revenue"], sum(float(o["Сумма, ₽"]) for o in source))
                    self.assertAlmostEqual(customer["average_order"], customer["revenue"] / customer["orders"], places=2)
                    self.assertEqual(customer["last_order_date"], max(o["Дата и время"][:10] for o in source))
                    self.assertEqual(customer["portion_rank"], ranks.index(customer["units"]) + 1)
                    self.assertEqual(sum(d["units"] for d in customer["dishes"]), customer["units"])
                    self.assertEqual(sum(d["orders"] for d in customer["dishes"]), customer["orders"])
                    self.assertEqual(customer["dishes"], sorted(customer["dishes"], key=lambda d: (-d["units"], -d["orders"], d["dish_id"])))
                    for dish in customer["dishes"]:
                        self.assertEqual(dish["units"], sum(int(o["Количество"]) for o in source if o["Блюдо"] == dish["dish_name"]))
        self.assertEqual(get("/api/customers?start=2025-01-01&end=2025-01-31")["rows"], [])
        for query, status in [("start=2026-06-01&end=2026-01-01", 422), ("restaurant=R1%27", 422), ("restaurant=R999", 404)]:
            with self.assertRaises(HTTPError) as error:
                get("/api/customers?" + query)
            self.assertEqual(error.exception.code, status)

    def test_analytics_and_filters(self):
        bootstrap = get("/api/bootstrap")
        dashboard = get("/api/dashboard")
        summary = dashboard["summary"]
        self.assertEqual(summary["orders"], bootstrap["processing"]["loaded"])
        self.assertEqual(sum(row["orders"] for row in dashboard["restaurants"]), summary["orders"])
        self.assertEqual(sum(row["orders"] for row in dashboard["fulfillment"]), summary["orders"])
        self.assertAlmostEqual(sum(row["revenue"] for row in dashboard["trend"]), summary["revenue"])
        restaurant = dashboard["restaurants"][0]
        filtered = get(f'/api/dashboard?restaurant={restaurant["restaurant_id"]}')
        self.assertEqual(filtered["summary"]["orders"], restaurant["orders"])
        self.assertEqual(len(filtered["restaurants"]), 1)
        self.assertAlmostEqual(sum(row["revenue"] for row in filtered["dishes"]), filtered["summary"]["revenue"])
        empty = get("/api/dashboard?start=2025-01-01&end=2025-01-31")
        self.assertEqual(empty["summary"]["orders"], 0)
        self.assertTrue(all(row["orders"] == 0 for row in empty["trend"]))
        for path in ["/api/dashboard?start=2026-06-01&end=2026-01-01", "/api/dashboard?restaurant=R1%27", "/api/quarantine?page=0"]:
            with self.assertRaises(HTTPError) as error:
                get(path)
            self.assertEqual(error.exception.code, 422)

    def test_csv_quarantine_and_runs(self):
        dashboard = get("/api/dashboard?restaurant=R1")
        with urlopen(BASE + "/api/export.csv?restaurant=R1", timeout=30) as response:
            rows = list(csv.reader(io.StringIO(response.read().decode("utf-8-sig")), delimiter=";"))
        self.assertEqual(len(rows)-1, dashboard["summary"]["orders"])
        self.assertAlmostEqual(sum(float(row[6]) for row in rows[1:]), dashboard["summary"]["revenue"])
        quality = get("/api/quality")
        s = quality["summary"]
        self.assertEqual(s["raw_rows"], s["loaded"]+s["quarantined"]+s["duplicates"]+s["unaccounted"])
        self.assertTrue(all(row["passed"] for row in quality["checks"]))
        reason = quality["reasons"][0]
        quarantine = get(f'/api/quarantine?reason={reason["reason"]}')
        self.assertEqual(quarantine["total"], reason["affected_raw_rows"])
        self.assertTrue(all(reason["reason"] in row["reasons"] for row in quarantine["rows"]))
        page2 = get("/api/quarantine?page=2")
        self.assertNotEqual(page2["rows"][0]["raw_id"], get("/api/quarantine")["rows"][0]["raw_id"])
        self.assertEqual(get("/api/quarantine?q=%27%20OR%20true%20--")["total"], 0)
        runs = get("/api/runs")["rows"]
        latest = runs[0]
        previous = next(row for row in runs if row["run_id"] == latest["previous_run_id"])
        self.assertEqual(latest["all_metrics_equal"], latest["metrics"] == previous["metrics"])


class Browser(unittest.TestCase):
    def test_restaurant_order_distribution(self):
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1512, "height": 1100}, locale="ru-RU")
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(BASE, wait_until="networkidle")
            page.get_by_role("button", name="Рестораны", exact=True).click()
            panel = page.locator(".order-distribution")
            expect(panel.get_by_role("heading", name="Когда заказывают чаще")).to_be_visible()
            expect(panel.get_by_role("img", name="Распределение заказов по часам суток")).to_be_visible()
            stats = page.locator(".stats-grid").inner_text()
            table = page.locator(".restaurant-table").inner_text()
            export = page.get_by_role("link", name="Экспорт CSV").get_attribute("href")
            requests = []
            page.on("request", lambda request: requests.append(request.url))
            panel.get_by_label("Рестораны для графика", exact=True).click()
            checkboxes = panel.get_by_role("checkbox")
            ids = [checkboxes.nth(i).input_value() for i in range(2)]
            for i in range(2):
                checkboxes.nth(i).check()
            orders = sum(get("/api/dashboard?restaurant=" + id)["summary"]["orders"] for id in ids)
            expected = page.evaluate("value => new Intl.NumberFormat('ru-RU').format(value) + ' заказов'", orders)
            expect(panel.locator(".count-tag")).to_have_text(expected)
            self.assertEqual(page.locator(".stats-grid").inner_text(), stats)
            self.assertEqual(page.locator(".restaurant-table").inner_text(), table)
            self.assertEqual(page.get_by_role("link", name="Экспорт CSV").get_attribute("href"), export)
            self.assertEqual(page.get_by_label("Ресторан", exact=True).input_value(), "")
            self.assertTrue(all("/api/orders-by-hour?" in url for url in requests if "/api/" in url))
            page.get_by_label("Ресторан", exact=True).select_option(ids[0])
            expect(page.locator(".restaurant-table tbody tr")).to_have_count(1)
            expect(panel.locator(".count-tag")).to_have_text(expected)
            page.screenshot(animations="disabled", path="/artifacts/restaurants-desktop.png", full_page=True)
            page.set_viewport_size({"width": 390, "height": 844})
            expect(panel.get_by_role("img", name="Распределение заказов по часам суток")).to_be_visible()
            if panel.locator("details").get_attribute("open") is None:
                panel.get_by_label("Рестораны для графика", exact=True).click()
            expect(checkboxes.nth(0)).to_be_checked()
            expect(checkboxes.nth(1)).to_be_checked()
            checkboxes.nth(1).uncheck()
            single_orders = get("/api/dashboard?restaurant=" + ids[0])["summary"]["orders"]
            expected = page.evaluate("value => new Intl.NumberFormat('ru-RU').format(value) + ' заказов'", single_orders)
            expect(panel.locator(".count-tag")).to_have_text(expected)
            panel.get_by_role("button", name="Все рестораны", exact=True).click()
            all_orders = get("/api/dashboard")["summary"]["orders"]
            expected = page.evaluate("value => new Intl.NumberFormat('ru-RU').format(value) + ' заказов'", all_orders)
            expect(panel.locator(".count-tag")).to_have_text(expected)
            expect(checkboxes.nth(0)).not_to_be_checked()
            self.assertLessEqual(page.evaluate("document.documentElement.scrollWidth"), 390)
            page.screenshot(animations="disabled", path="/artifacts/restaurants-mobile.png", full_page=True)
            page.get_by_label("Начало периода").fill("2025-01-01")
            page.get_by_label("Конец периода").fill("2025-01-31")
            expect(panel.get_by_text("Заказов за этот период нет", exact=True)).to_be_visible()
            expect(panel.locator(".count-tag")).to_have_text("0 заказов")
            self.assertEqual(errors, [])
            browser.close()

    def test_dashboard_navigation_export_and_mobile(self):
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1512, "height": 1100}, device_scale_factor=1, locale="ru-RU", timezone_id="Europe/Moscow")
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            response = page.goto(BASE, wait_until="networkidle")
            self.assertEqual(response.status, 200)
            summary = get("/api/dashboard")["summary"]
            revenue = page.evaluate("value => new Intl.NumberFormat('ru-RU', {style: 'currency', currency: 'RUB', maximumFractionDigits: 0}).format(value)", summary["revenue"])
            expect(page.locator(".stat-value").first).to_have_text(revenue, timeout=30000)
            expect(page.get_by_role("heading", name="Бизнес в деталях")).to_be_visible()
            page.evaluate("window.scrollTo(0, 0)")
            page.screenshot(animations="disabled", path="/artifacts/dashboard-desktop.png", full_page=True)
            with page.expect_download() as download:
                page.get_by_role("link", name="Экспорт CSV").click()
            self.assertTrue(download.value.suggested_filename.endswith(".csv"))
            page.get_by_label("Ресторан", exact=True).select_option("R1")
            restaurant_orders = get("/api/dashboard?restaurant=R1")["summary"]["orders"]
            expect(page.locator(".stat").nth(1).locator(".stat-value")).to_have_text(str(restaurant_orders), timeout=30000)
            page.get_by_label("Ресторан", exact=True).select_option("")
            expect(page.locator(".stat").nth(1).locator(".stat-value")).to_contain_text("6", timeout=30000)
            page.get_by_role("button", name="90 дней", exact=True).click()
            expect(page.get_by_label("Начало периода")).to_have_value("2026-03-26")
            page.get_by_role("button", name="Весь период", exact=True).click()
            page.get_by_role("button", name="Рестораны", exact=True).click()
            expect(page.get_by_role("heading", name="Показатели ресторанов")).to_be_visible()
            page.get_by_role("button", name="Блюда", exact=True).click()
            expect(page.get_by_role("heading", name="Рейтинг блюд")).to_be_visible()
            page.get_by_role("button", name="Клиенты", exact=True).click()
            expect(page.get_by_role("heading", name="Главный гурман")).to_be_visible(timeout=30000)
            clients = get("/api/customers")["rows"]
            expect(page.locator(".gourmet-score strong")).to_have_text(str(clients[0]["units"]))
            expect(page.locator(".customer-name")).to_have_count(len(clients))
            page.locator(".customer-name").first.click()
            expect(page.locator(".customer-dishes>div")).to_have_count(len(clients[0]["dishes"]))
            page.get_by_label("Поиск клиента", exact=True).fill(clients[0]["customer_id"])
            expect(page.locator(".customer-name")).to_have_count(1)
            page.get_by_label("Поиск клиента", exact=True).fill("НЕСУЩЕСТВУЮЩИЙ_КЛИЕНТ")
            expect(page.get_by_text("Клиент не найден", exact=True)).to_be_visible()
            page.get_by_label("Очистить поиск клиента").click()
            page.get_by_role("button", name="Потрачено", exact=True).click()
            expect(page.locator(".customer-name").first).to_contain_text(max(clients, key=lambda c: c["revenue"])["full_name"])
            page.get_by_role("button", name="Порции", exact=True).click()
            page.locator(".customer-name").first.click()
            page.evaluate("window.scrollTo(0, 0)")
            page.screenshot(animations="disabled", path="/artifacts/customers-desktop.png", full_page=True)
            page.get_by_label("Ресторан", exact=True).select_option("R1")
            filtered_clients = get("/api/customers?restaurant=R1")["rows"]
            expect(page.locator(".gourmet-score strong")).to_have_text(str(filtered_clients[0]["units"]), timeout=30000)
            expect(page.locator(".gourmet-names")).to_contain_text(filtered_clients[0]["full_name"])
            page.get_by_label("Ресторан", exact=True).select_option("")
            expect(page.locator(".gourmet-score strong")).to_have_text(str(clients[0]["units"]), timeout=30000)
            page.get_by_label("Начало периода").fill("2026-01-06")
            page.get_by_label("Конец периода").fill("2026-01-06")
            tied = [c for c in get("/api/customers?start=2026-01-06&end=2026-01-06")["rows"] if c["portion_rank"] == 1]
            self.assertGreater(len(tied), 1)
            expect(page.locator(".customer-winner")).to_have_count(len(tied), timeout=30000)
            expect(page.locator(".gourmet-score span")).to_have_text("порций у каждого")
            for customer in tied:
                expect(page.locator(".gourmet-names")).to_contain_text(customer["full_name"])
            page.get_by_role("button", name="Весь период", exact=True).click()
            page.get_by_role("navigation").get_by_role("button", name="Качество данных", exact=False).click()
            expect(page.get_by_role("heading", name="Каждая строка под контролем")).to_be_visible(timeout=30000)
            expect(page.locator(".quarantine-record")).to_have_count(12, timeout=30000)
            page.get_by_role("button", name="Следующая страница").click()
            expect(page.get_by_text("Страница 2 из", exact=False)).to_be_visible(timeout=30000)
            page.locator(".quarantine-record-head").first.click()
            expect(page.locator(".record-details")).to_be_visible()
            page.get_by_role("button", name="Исправить запись", exact=True).click()
            expect(page.get_by_role("heading", name="Исправить и загрузить", exact=True)).to_be_visible()
            expect(page.get_by_label("Количество порций", exact=True)).to_be_visible()
            expect(page.get_by_label("Клиент", exact=True).locator("option")).not_to_have_count(1)
            page.get_by_role("button", name="Закрыть исправление", exact=True).click()
            page.get_by_label("Поиск по карантину").fill("НЕСУЩЕСТВУЮЩАЯ_ЗАПИСЬ_000")
            expect(page.get_by_text("Записи не найдены", exact=True)).to_be_visible(timeout=30000)
            page.get_by_label("Очистить поиск").click()
            expect(page.locator(".quarantine-record")).to_have_count(12, timeout=30000)
            page.evaluate("window.scrollTo(0, 0)")
            page.screenshot(animations="disabled", path="/artifacts/quality-desktop.png", full_page=True)
            runs = get("/api/runs")["rows"]
            page.get_by_role("button", name="История загрузок", exact=True).click()
            expect(page.locator(".run-card")).to_have_count(len(runs), timeout=30000)
            comparison = 'полностью совпадает с загрузкой' if runs[0]['all_metrics_equal'] else 'отличается от загрузки'
            expect(page.locator('.run-card').first).to_contain_text(f"Результат {comparison} #{runs[0]['previous_run_id']}")
            page.get_by_role("button", name="Обзор", exact=True).click()
            page.set_viewport_size({"width": 390, "height": 844})
            expect(page.get_by_label("Открыть меню")).to_be_visible()
            self.assertLessEqual(page.evaluate("document.documentElement.scrollWidth"), 390)
            page.evaluate("window.scrollTo(0, 0)")
            page.screenshot(animations="disabled", path="/artifacts/dashboard-mobile.png", full_page=True)
            page.get_by_label("Открыть меню").click()
            page.get_by_role("button", name="Клиенты", exact=True).click()
            expect(page.get_by_role("heading", name="Главный гурман")).to_be_visible(timeout=30000)
            self.assertLessEqual(page.evaluate("document.documentElement.scrollWidth"), 390)
            page.evaluate("window.scrollTo(0, 0)")
            page.screenshot(animations="disabled", path="/artifacts/customers-mobile.png", full_page=True)
            page.get_by_label("Начало периода").fill("2025-01-01")
            page.get_by_label("Конец периода").fill("2025-01-31")
            expect(page.get_by_text("Заказов за этот период нет", exact=True)).to_be_visible(timeout=30000)
            expect(page.locator(".gourmet-award")).to_have_count(0)
            page.get_by_role("button", name="Весь период", exact=True).click()
            page.get_by_label("Открыть меню").click()
            page.get_by_role("navigation").get_by_role("button", name="Качество данных", exact=False).click()
            expect(page.get_by_role("heading", name="Данным можно доверять")).to_be_visible()
            self.assertLessEqual(page.evaluate("document.documentElement.scrollWidth"), 390)
            self.assertEqual(errors, [])
            browser.close()


if __name__ == "__main__":
    Path("/artifacts").mkdir(parents=True, exist_ok=True)
    unittest.main(verbosity=2)
