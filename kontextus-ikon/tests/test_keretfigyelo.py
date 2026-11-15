"""A keretfigyelő (keretfigyelo.py) és a statusline közös fiók-lekérdezésének tesztjei (E1-E6, T02 feladatlap).

    python3 -m unittest discover -s kontextus-ikon/tests -p 'test_*.py' -v

A HTTP-válaszok és az app-server üzenetei kézzel írt minták (tests/fixtures/claude, tests/fixtures/appserver);
valódi hálózat, valódi token és valódi Codex nincs. A „most” rögzített (T0), a döntések ezt kapják.
KERETFIGYELO_SRC: a tesztelt forrásmappa (alapból a repóbeli; a mutants.sh a hibás másolatra állítja)."""
import contextlib
import fcntl
import http.client
import importlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.environ.get("KERETFIGYELO_SRC") or os.path.dirname(HERE)
sys.path.insert(0, SRC)
import statusline as S  # noqa: E402
import keretfigyelo as K  # noqa: E402

FX = os.path.join(HERE, "fixtures")
CRED = os.path.join(FX, "claude", "credentials.json")
CRED_OLD = os.path.join(FX, "claude", "credentials-lejart.json")
TOKEN = "MINTA-TOKEN-ne-latszodjon-7f3a"
REFRESH = "MINTA-REFRESH-9c1d"
FAKE_SERVER = os.path.join(FX, "appserver", "minta_app_server.py")
T0 = 1794746760.0          # 2026-11-15 12:46 UTC
RESET_5H = 1794756480.0    # a minták 5 órás visszaállása
RESET_WEEK = 1795111200.0  # a Claude-minta heti visszaállása (2026-11-19 18:00 UTC)


def read(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


def usage_bytes():
    return read(os.path.join(FX, "claude", "usage.json"), "rb")


class Opener:
    """urlopen-helyettesítő: számolja a hívásokat; a válasz a minta vagy a megadott kivétel."""

    def __init__(self, body=None, error=None):
        self.body, self.error, self.calls, self.headers = body, error, 0, []

    def __call__(self, req, timeout):
        self.calls += 1
        self.headers.append(dict(req.header_items()))
        if self.error:
            raise self.error
        return io.BytesIO(self.body if self.body is not None else usage_bytes())


def http_error(code):
    return urllib.error.HTTPError(S.USAGE_URL, code, "minta", {"WWW-Authenticate": "Bearer"}, io.BytesIO(b"{}"))


class Tmp(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="keretfigyelo-teszt-")
        self.cache = os.path.join(self.dir, "cache", "claude-account-usage.json")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def usage(self, now=T0, opener=None, cred=CRED, wait=True):
        return S.account_usage(now, cred_path=cred, cache_path=self.cache, opener=opener or Opener(), wait=wait)


# ---- E1: Claude bejelentkezve ---------------------------------------------------

class E1Claude(Tmp):
    def test_E1_valasz_feldolgozasa(self):
        rows, resets, windows = S.parse_usage(json.loads(usage_bytes()))
        self.assertEqual(windows["five_hour"], {"pct": 30, "resets_at": RESET_5H})
        self.assertEqual(windows["seven_day"], {"pct": 53, "resets_at": RESET_WEEK})
        self.assertEqual(rows, {"Fable": 21})
        self.assertEqual(resets, {"Fable": RESET_WEEK})

    def test_E1_legfeljebb_2_percenkent_kozos_gyorsitotar(self):
        op = Opener()
        self.usage(T0, op)
        self.usage(T0 + S.USAGE_EVERY - 1, op)             # a gyorsítótárból: nincs új kérés
        self.assertEqual(op.calls, 1)
        self.usage(T0 + S.USAGE_EVERY, op)
        self.assertEqual(op.calls, 2)
        self.assertEqual(S.USAGE_EVERY, 120)

    def test_E1_statusline_nem_var_ha_mas_kerdez(self):
        self.usage(T0, Opener())
        os.makedirs(os.path.dirname(self.cache), exist_ok=True)
        op = Opener()
        with open(self.cache + ".lock", "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            c = self.usage(T0 + 999, op, wait=False)        # lejárt gyorsítótár, de a zárat más fogja
        self.assertEqual(op.calls, 0)
        self.assertEqual(c["ok_at"], T0)

    def test_E1_figyelo_blokk(self):
        b = K.claude_block(self.usage())
        self.assertEqual(b["five_hour"], {"pct": 30, "resets_at": RESET_5H, "ts": T0, "source": "fiók"})
        self.assertEqual(b["seven_day"]["pct"], 53)
        self.assertEqual(b["fable"]["pct"], 21)
        self.assertEqual(b["fable"]["resets_at"], RESET_WEEK)
        self.assertIsNone(b["why"])

    def test_E1_statusline_sorai_valtozatlanok(self):
        with mock.patch.object(S, "CREDENTIALS", CRED), mock.patch.object(S, "USAGE_CACHE", self.cache), \
                mock.patch("urllib.request.urlopen", Opener()):
            rows, resets, ok_at = S.account_model_rows()
        self.assertEqual(rows, {"Fable": 21})
        self.assertEqual(resets, {"Fable": RESET_WEEK})
        self.assertIsNotNone(ok_at)


# ---- E2: nincs bejelentkezés, lejárt token ---------------------------------------

class E2Claude(Tmp):
    def test_E2_nincs_hitelesito_fajl(self):
        op = Opener()
        c = self.usage(opener=op, cred=os.path.join(self.dir, "nincs.json"))
        self.assertEqual(c["why"], "nincs Claude-bejelentkezés")
        self.assertEqual(op.calls, 0)
        self.assertNotIn("five_hour", K.claude_block(c))

    def test_E2_401_lejart_az_utolso_jo_adat_marad(self):
        self.usage(T0, Opener())
        c = self.usage(T0 + 600, Opener(error=http_error(401)))
        self.assertEqual(c["why"], "a Claude-bejelentkezés lejárt (401)")
        self.assertEqual(c["ok_at"], T0)
        b = K.claude_block(c)
        self.assertEqual(b["seven_day"]["ts"], T0)       # a régi adat a régi idejével: a bővítmény régiként mutatja

    def test_E2_lejart_token_kereses_nelkul(self):
        op = Opener()
        c = self.usage(opener=op, cred=CRED_OLD)
        self.assertEqual(c["why"], "a Claude-bejelentkezés lejárt")
        self.assertEqual(op.calls, 0)

    def test_E2_hibas_sema_hibakent_gyorsitotarba_kerul(self):
        self.usage(T0, Opener())
        bad = json.dumps({"limits": [{"percent": 5, "kind": "weekly_scoped", "scope": {"model": "Fable"}}]}).encode()
        op = Opener(body=bad)
        c = self.usage(T0 + S.USAGE_EVERY, op)
        self.assertTrue(c["why"].startswith("hibás válasz (ismeretlen formátum"), c["why"])
        self.assertEqual(c["rows"], {"Fable": 21})          # az utolsó jó adat marad
        self.assertEqual(c["ok_at"], T0)
        self.usage(T0 + S.USAGE_EVERY + 1, op)              # a hiba is gyorsítótárban: nincs új kérés
        self.assertEqual(op.calls, 1)

    def test_E2_csonka_torzs_hibakent_gyorsitotarba_kerul(self):
        self.usage(T0, Opener())

        class Cut(io.BytesIO):
            def read(self, *a):
                raise http.client.IncompleteRead(b'{"limits": [', 100)
        calls = []

        def opener(req, timeout):
            calls.append(1)
            return Cut()
        c = self.usage(T0 + S.USAGE_EVERY, opener)
        self.assertEqual(c["why"], "hálózati hiba (IncompleteRead)")
        self.assertEqual(c["windows"]["seven_day"]["pct"], 53)
        self.usage(T0 + S.USAGE_EVERY + 1, opener)
        self.assertEqual(len(calls), 1)

    def test_E2_halozati_hiba_oka(self):
        c = self.usage(opener=Opener(error=urllib.error.URLError("nincs hálózat")))
        self.assertTrue(c["why"].startswith("hálózati hiba"), c["why"])


# ---- 3. feltétel: a token csak olvasva, soha nem írva, nem naplózva ----------------

class TokenSafety(Tmp):
    def test_token_nem_irodik_nem_naplozodik(self):
        cred = os.path.join(self.dir, "credentials.json")
        shutil.copy(CRED, cred)
        before = (read(cred, "rb"), os.stat(cred).st_mtime_ns)
        out, err = io.StringIO(), io.StringIO()
        op = Opener()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.usage(T0, op, cred=cred)
            c = self.usage(T0 + 600, Opener(error=http_error(401)), cred=cred)
            K.log(f"Claude: {c['why']}")
            state = os.path.join(self.dir, "run", "keretfigyelo.json")
            K.write_state(state, K.build_state(K.claude_block(c), {}, T0, T0))
        self.assertEqual(op.headers[0]["Authorization"], f"Bearer {TOKEN}")   # a token valóban a kérésbe ment
        self.assertEqual((read(cred, "rb"), os.stat(cred).st_mtime_ns), before)
        for name, text in (("stdout", out.getvalue()), ("stderr", err.getvalue()),
                           ("gyorsítótár", read(self.cache)), ("állapotfájl", read(state))):
            for secret in (TOKEN, REFRESH, "Bearer", "WWW-Authenticate"):
                self.assertNotIn(secret, text, f"{secret} a(z) {name} tartalmában")


# ---- 4. feltétel: atomikus írás ----------------------------------------------------

class AtomicWrite(Tmp):
    def test_allapotfajl_ideiglenes_fajl_es_atnevezes(self):
        path = os.path.join(self.dir, "run", "keretfigyelo.json")
        with mock.patch("os.replace", wraps=os.replace) as rep:
            K.write_state(path, {"ts": T0})
        rep.assert_called_once()
        tmp, dst = rep.call_args[0]
        self.assertEqual(dst, path)
        self.assertNotEqual(tmp, path)
        self.assertEqual(os.path.dirname(tmp), os.path.dirname(path))   # ugyanazon a fájlrendszeren
        self.assertEqual(os.listdir(os.path.dirname(path)), ["keretfigyelo.json"])
        self.assertEqual(json.loads(read(path)), {"ts": T0})


# ---- E3, E4: Codex app-server ------------------------------------------------------

def fake(scenario, log):
    return [sys.executable, "-I", FAKE_SERVER, scenario, log]


def pump(codex, until, now=T0, limit=5.0):
    """Események feldolgozása, amíg until() igaz nem lesz (legfeljebb limit valódi mp)."""
    end = time.monotonic() + limit
    while not until() and time.monotonic() < end:
        codex.step(now, 0.2)
    return until()


class CodexBase(Tmp):
    def codex(self, scenario, **kw):
        self.log = os.path.join(self.dir, "kapott.jsonl")
        c = K.Codex(command=fake(scenario, self.log), **kw)
        self.addCleanup(c.stop)
        return c

    def sent(self):
        try:
            with open(self.log, encoding="utf-8") as f:
                return [json.loads(x) for x in f]
        except FileNotFoundError:
            return []

    def first_read(self, c, now=T0):
        c.tick(now)
        self.assertTrue(pump(c, lambda: c.ready, now), "nincs initialize-válasz")
        c.tick(now)
        self.assertTrue(pump(c, lambda: c.answers, now), "nincs válasz a lekérésre")


class E3Codex(CodexBase):
    def test_E3_kezfogas_es_lekeres(self):
        c = self.codex("ok")
        self.first_read(c)
        msgs = self.sent()
        self.assertEqual([m["method"] for m in msgs], ["initialize", "initialized", "account/rateLimits/read"])
        self.assertEqual(msgs[0]["params"]["clientInfo"]["name"], "kontextus_keretfigyelo")
        self.assertIn("id", msgs[0])
        self.assertNotIn("id", msgs[1])                      # az initialized értesítés, nincs id
        self.assertEqual(msgs[2]["params"], {"excludeResetCreditDetails": True})
        b = c.block()
        self.assertEqual(b["five_hour"], {"pct": 20, "resets_at": RESET_5H, "ts": T0, "window_minutes": 300,
                                          "source": "app-server"})
        self.assertEqual(b["weekly"]["pct"], 47)
        self.assertEqual(b["plan"], "plus")
        self.assertIsNone(b["why"])

    def test_E3_percenkenti_lekeres(self):
        c = self.codex("ok")
        self.first_read(c)
        c.tick(T0 + K.CODEX_EVERY - 1)
        self.assertEqual(len(c.pending), 0, "korai lekérés")
        c.tick(T0 + K.CODEX_EVERY)
        self.assertEqual(len(c.pending), 1, "nincs lekérés egy perc után")
        self.assertEqual(K.CODEX_EVERY, 60)

    def test_E3_ertesites_azonnal_frissit(self):
        c = self.codex("ertesites")
        self.first_read(c)
        self.assertTrue(pump(c, lambda: c.block().get("five_hour", {}).get("pct") == 35, T0 + 5))
        b = c.block()
        self.assertEqual(b["five_hour"]["ts"], T0 + 5)
        self.assertEqual(b["weekly"], {"pct": 47, "resets_at": 1795005960, "ts": T0, "window_minutes": 10080,
                                       "source": "app-server"})   # a ritka értesítés a másik ablakot nem törli
        self.assertEqual([m["method"] for m in self.sent()].count("account/rateLimits/read"), 1)

    def test_E3_idegen_limit_id_kimarad(self):
        c = self.codex("ertesites-masik")
        self.first_read(c)
        pump(c, lambda: False, T0 + 5, limit=0.6)
        self.assertEqual(c.block()["five_hour"]["pct"], 20)

    def test_E3_ablak_a_hossza_szerint(self):
        snap = {"primary": {"usedPercent": 47, "windowDurationMins": 10080, "resetsAt": 2},
                "secondary": {"usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1}}
        w = K.codex_windows(snap, T0)
        self.assertEqual(w["five_hour"]["pct"], 20)
        self.assertEqual(w["weekly"]["pct"], 47)


class E4Codex(CodexBase):
    def test_E4_nincs_telepitve(self):
        c = K.Codex()
        with mock.patch.dict(os.environ, {"PATH": self.dir, "HOME": self.dir}), \
                mock.patch.dict(os.environ, {}, clear=False) as env:
            env.pop("KERETFIGYELO_CODEX", None)
            with contextlib.redirect_stderr(io.StringIO()):
                c.tick(T0)
        self.assertEqual(c.why, "a Codex nincs telepítve (nincs codex parancs)")
        self.assertEqual(c.next_start, T0 + K.BACKOFF[0])

    def test_E4_nincs_bejelentkezve(self):
        c = self.codex("nincs-bejelentkezes")
        with contextlib.redirect_stderr(io.StringIO()):
            self.first_read(c)
        self.assertEqual(c.why, "nincs Codex-bejelentkezés")
        self.assertNotIn("five_hour", c.block())

    def test_E4_api_kulcs(self):
        c = self.codex("apikulcs")
        with contextlib.redirect_stderr(io.StringIO()):
            self.first_read(c)
        self.assertIn("API-kulcs", c.why)

    def test_E4_kilep_ujrainditas_novekvo_varakozassal(self):
        c = self.codex("kilep")
        with contextlib.redirect_stderr(io.StringIO()):
            c.tick(T0)
            self.assertTrue(pump(c, lambda: c.failures == 1, T0))
            self.assertEqual(c.why, "a Codex app-server kilépett (kód 3)")
            self.assertEqual(c.next_start, T0 + 5)
            c.tick(T0 + 4)
            self.assertIsNone(c.proc, "túl korai újraindítás")
            c.tick(T0 + 5)
            self.assertIsNotNone(c.proc, "nincs újraindítás")
            self.assertTrue(pump(c, lambda: c.failures == 2, T0 + 5))
        self.assertEqual(c.next_start, T0 + 5 + 15)

    def test_E4_nem_valaszol_idokorlat(self):
        c = self.codex("nem-valaszol", timeout=10)
        with contextlib.redirect_stderr(io.StringIO()):
            self.first_read_no_answer(c)
            c.tick(T0 + 10)
            self.assertIsNotNone(c.proc, "túl korai időkorlát")
            c.tick(T0 + 11)
            pump(c, lambda: False, T0 + 12, limit=1.0)   # a leállított folyamat késő kilépés-eseménye
        self.assertIsNone(c.proc)
        self.assertIn("nem válaszolt", c.why)
        self.assertEqual(c.failures, 1, "a saját leállítás kilépése második hibának számított")
        self.assertEqual(c.next_start, T0 + 11 + 5)

    def first_read_no_answer(self, c):
        c.tick(T0)
        self.assertTrue(pump(c, lambda: c.ready))
        c.tick(T0)
        self.assertEqual(len(c.pending), 1)

    def test_E4_nem_json_sor_kimarad(self):
        c = self.codex("szemet")
        self.first_read(c)
        self.assertEqual(c.block()["five_hour"]["pct"], 20)

    def test_E4_backoff_novekszik_es_korlatos(self):
        self.assertEqual([K.backoff(n) for n in range(1, 8)], [5, 15, 60, 300, 900, 900, 900])


class E4Sema(CodexBase):
    def test_E4_nem_vart_alaku_uzenetek_kimaradnak(self):
        c = self.codex("hibas-sema")
        with contextlib.redirect_stderr(io.StringIO()):
            self.first_read(c)                              # szöveges error: kivétel nélkül, konkrét ok
        self.assertEqual(c.why, "a Codex app-server hibát adott: szöveges hiba")
        c.tick(T0 + K.CODEX_EVERY)
        self.assertTrue(pump(c, lambda: c.answers == 2, T0 + K.CODEX_EVERY), "nincs második válasz")
        pump(c, lambda: False, T0 + K.CODEX_EVERY, limit=0.6)
        self.assertEqual(c.why, "a Codex-válaszban nincs codex keret")
        self.assertNotIn("five_hour", c.block())
        self.assertIsNotNone(c.proc, "az app-server leállt")


class Once(CodexBase):
    def test_once_friss_lekeres_a_kozos_gyorsitotar_nelkul(self):
        seen = {}

        def usage(now, **kw):
            seen.update(kw)
            seen["exists"] = os.path.isdir(os.path.dirname(kw["cache_path"]))
            return {"at": now, "ok_at": now, "rows": {"Fable": 21}, "resets": {}, "windows": {}, "why": None}
        with mock.patch.object(S, "account_usage", usage):
            r = K.once(timeout=5, codex=self.codex("ok"))
        self.assertNotEqual(os.path.abspath(seen["cache_path"]), os.path.abspath(S.USAGE_CACHE))
        self.assertTrue(seen["exists"])
        self.assertFalse(os.path.exists(os.path.dirname(seen["cache_path"])), "az ideiglenes gyorsítótár megmaradt")
        self.assertEqual(r["claude"]["fable"]["pct"], 21)
        self.assertEqual(r["codex"]["five_hour"]["pct"], 20)


# ---- a szolgáltatás ciklusa: nem akad el, leállításkor eltávolítja az állapotfájlt (E4, E6) ----------

class Loop(Tmp):
    def test_ciklus_hibas_codexszel_is_ir_es_leallaskor_torol(self):
        path = os.path.join(self.dir, "run", "keretfigyelo.json")
        codex = K.Codex(command=fake("kilep", os.path.join(self.dir, "kapott.jsonl")))
        stop = threading.Event()
        usage = {"at": T0, "ok_at": T0, "rows": {"Fable": 21}, "resets": {}, "windows": {}, "why": None}
        with mock.patch.object(S, "account_usage", lambda *a, **k: usage), \
                contextlib.redirect_stderr(io.StringIO()):
            th = threading.Thread(target=K.run, args=(path,), kwargs={"stop": stop, "codex": codex})
            th.start()
            end = time.monotonic() + 5
            state = None
            while time.monotonic() < end:
                try:
                    state = json.loads(read(path))
                    if state["codex"]["why"] and "kilépett" in state["codex"]["why"]:
                        break
                except (OSError, ValueError, KeyError, TypeError):
                    pass
                time.sleep(0.05)
            stop.set()
            th.join(5)
        self.assertFalse(th.is_alive(), "a ciklus nem állt le")
        self.assertEqual(state["claude"]["fable"]["pct"], 21)
        self.assertIn("kilépett", state["codex"]["why"])
        self.assertFalse(os.path.exists(path), "leállás után megmaradt az állapotfájl")


# ---- 6. feltétel: systemd-egység, útvonal-függetlenül --------------------------------

class Unit(Tmp):
    def test_egyseg_szokozos_utvonallal(self):
        tpl = os.path.join(SRC, "keretfigyelo.service.in")
        text = K.render_unit(tpl, "/usr/bin/python3", "/home/a b/klón 50%/$x/keretfigyelo.py", "/a b:/usr/bin")
        self.assertIn('ExecStart="/usr/bin/python3" "/home/a b/klón 50%%/$$x/keretfigyelo.py"\n', text)
        self.assertIn('Environment="PATH=/a b:/usr/bin"\n', text)
        self.assertNotIn("@", text.split("[Unit]")[1])


if __name__ == "__main__":
    unittest.main()
