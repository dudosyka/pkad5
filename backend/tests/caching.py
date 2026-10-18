import json
import os
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright, expect

BASE = os.environ.get("BASE_URL", "http://frontend")


def read(path, etag=None):
    request = Request(BASE + path, headers={"If-None-Match": etag} if etag else {})
    try:
        response = urlopen(request, timeout=30)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        return response.status, response.headers, json.loads(body) if body else None


class Cache(unittest.TestCase):
    def test_api_reuses_results_and_separates_filters(self):
        path = "/api/dashboard?start=2026-01-01&end=2026-06-23&granularity=day"
        status, headers, original = read(path)
        self.assertEqual(status, 200)
        self.assertEqual(headers["Cache-Control"], "private, no-cache")
        status, repeated_headers, repeated = read(path)
        self.assertEqual(repeated_headers["X-Cache"], "HIT")
        self.assertEqual(repeated, original)
        self.assertEqual(read(path, headers["ETag"])[0], 304)
        self.assertEqual(read(path, 'W/' + headers["ETag"])[0], 304)
        for filtered in (path + "&restaurant=R1", path.replace("granularity=day", "granularity=month")):
            status, new_headers, _ = read(filtered, headers["ETag"])
            self.assertEqual(status, 200)
            self.assertNotEqual(headers["ETag"], new_headers["ETag"])

        _, first_headers, _ = read(path + "&restaurant=R1&restaurant=R2")
        status, _, result = read(path + "&restaurant=R2&restaurant=R1", first_headers["ETag"])
        self.assertEqual(status, 200)
        self.assertEqual(result["restaurants"][0]["restaurant_id"], "R1")
        for _ in range(2):
            status, error_headers, _ = read("/api/dashboard?restaurant=R999")
            self.assertEqual(status, 404)
            self.assertIsNone(error_headers["ETag"])
            self.assertEqual(error_headers["Cache-Control"], "no-store")

    def test_reload_renders_before_revalidation_and_keeps_charts(self):
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(BASE, wait_until="networkidle")
            expect(page.locator(".stat-value")).to_have_count(4)
            previous = page.locator(".stat-value").all_text_contents()
            self.assertTrue(page.evaluate("localStorage.getItem('srez-api-cache') !== null"))
            pending = []
            statuses = []
            page.route("**/api/**", lambda route: pending.append(route))
            page.on("response", lambda response: statuses.append(response.status) if "/api/" in response.url else None)
            with page.expect_request("**/api/bootstrap"), page.expect_request("**/api/dashboard?**"):
                page.reload(wait_until="domcontentloaded")

            expect(page.locator(".stat-value")).to_have_text(previous)
            expect(page.locator(".loading-state")).to_have_count(0)
            expect(page.locator(".analytics-content")).to_have_attribute("aria-busy", "false")
            self.assertEqual(len(pending), 2)
            for route in pending:
                self.assertIn("if-none-match", route.request.headers)
                route.continue_()
            page.wait_for_load_state("networkidle")
            self.assertEqual(statuses, [304, 304])
            expect(page.locator(".stat-value")).to_have_text(previous)
            self.assertEqual(errors, [])
            browser.close()

    def test_unavailable_storage_still_loads(self):
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            page.add_init_script("Storage.prototype.setItem = () => { throw new DOMException('No storage'); };")
            page.goto(BASE, wait_until="networkidle")
            expect(page.locator(".stat-value")).to_have_count(4)
            expect(page.locator(".error-box")).to_have_count(0)
            browser.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
