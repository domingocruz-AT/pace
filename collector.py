"""Read-only usage collector. User approved existing Codex sign-in on 2026-10-11.

Credentials remain in memory, are never logged, and are sent only to the fixed
OpenAI origin below. No redirects, credential refresh, or billing mutations.
"""
import argparse
import datetime as dt
import json
import math
import pathlib
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = 'https://chatgpt.com/backend-api'
ROUTES = frozenset(('/wham/usage/daily-workspace-user-credit-usage', '/wham/usage/credits/estimate', '/wham/usage/daily-workspace-user-token-usage-breakdown'))

class SchemaError(Exception):
    pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def amount(value):
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0:
        raise SchemaError('Invalid usage amount')
    return float(value)


def normalize(history, estimate, start, end):
    if not isinstance(history, dict) or not isinstance(history.get('series'), list) or not isinstance(history.get('data'), list):
        raise SchemaError('Unsupported usage response')
    total = sum(amount(series['total']) for series in history['series'])
    rows = {}
    for row in history['data']:
        day = dt.date.fromisoformat(row['date'])
        if day in rows or not start <= day <= end or not isinstance(row['values'], dict):
            raise SchemaError('Invalid date range')
        rows[day] = sum(amount(value) for value in row['values'].values())
    # Detect schema changes or mismatched series before showing misleading totals.
    if not math.isclose(sum(rows.values()), total, rel_tol=1e-6, abs_tol=0.01):
        raise SchemaError('Daily and aggregate amounts disagree')
    dollars = amount(estimate['estimated_usage_usd_micros']) / 1_000_000
    daily = [{'date': (start + dt.timedelta(days=i)).isoformat(), 'credits': rows.get(start + dt.timedelta(days=i), 0)} for i in range((end-start).days + 1)]
    freshness = history.get('data_freshness_ts')
    if freshness is not None and not isinstance(freshness, str):
        raise SchemaError('Invalid freshness')
    return {'state': 'ok', 'message': '', 'dataAsOf': freshness, 'credits': total,
            'estimatedUSD': dollars, 'todayCredits': rows.get(end, 0), 'daily': daily}


def token_rows(payload, start, end):
    rows = {}
    for row in payload['data']:
        day = dt.date.fromisoformat(row['date'])
        if not start <= day <= end or str(day) in rows:
            raise SchemaError('Invalid token date')
        models = {}
        for group in row.get('groups', row.get('models', [])):
            model = group.get('model') or ('other' if group.get('is_other') else group.get('dimensions', {}).get('model'))
            if not isinstance(model, str) or not model:
                raise SchemaError('Missing model')
            components = [amount(group.get(k, 0)) for k in ('uncached_text_input_tokens', 'cached_text_input_tokens', 'text_output_tokens')]
            total = amount(group.get('text_total_tokens') or sum(components))
            models[model] = models.get(model, 0) + total
        rows[str(day)] = models
    return rows


def collect(end=None, days=30):
    auth = json.loads((pathlib.Path.home() / '.codex' / 'auth.json').read_text())
    tokens = auth.get('tokens') or {}
    token = tokens.get('access_token')
    account = tokens.get('account_id')
    if not isinstance(token, str) or not token or not isinstance(account, str) or not account:
        return {'state': 'auth', 'message': 'Sign in with ChatGPT in Codex, then refresh.'}
    headers = {'Authorization': 'Bearer ' + token, 'ChatGPT-Account-ID': account,
               'Accept': 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'CodexUsage/1.0'}
    # Ignore inherited proxy variables: requests go directly to the fixed origin.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    def request(route, query=None, body=None):
        if route not in ROUTES:
            raise ValueError('Unsupported route')
        url = ORIGIN + route + ('?' + urllib.parse.urlencode(query, doseq=True) if query else '')
        req = urllib.request.Request(url, headers=headers, data=json.dumps(body).encode() if body is not None else None)
        with opener.open(req, timeout=15) as response:
            raw = response.read(1_048_577)
            if len(raw) > 1_048_576:
                raise SchemaError('Unexpected response size')
            return json.loads(raw)
    today = dt.datetime.now(dt.timezone.utc).date()
    end = end or today
    if end > today or days < 1 or days > 90:
        raise ValueError("Invalid date range")
    start = end - dt.timedelta(days=days - 1)
    # The source's bounded requests are combined without overlapping days.
    histories, tokens_by_day, token_ok, token_freshness = [], {}, True, []
    cursor = start
    while cursor <= end:
        chunk_end = min(end, cursor + dt.timedelta(days=29))
        query = {'start_date': str(cursor), 'end_date': str(chunk_end)}
        part = request('/wham/usage/daily-workspace-user-credit-usage', dict(query, breakdown='model'))
        # Validate each chunk before merging it with the rest.
        normalize(part, {'estimated_usage_usd_micros': 0}, cursor, chunk_end)
        histories.append(part)
        try:
            token_payload = request('/wham/usage/daily-workspace-user-token-usage-breakdown', dict(query, group_by='day', breakdown_by='model', modes=['codex', 'work']))
            tokens_by_day.update(token_rows(token_payload, cursor, chunk_end))
            if isinstance(token_payload.get('data_freshness_ts'), str):
                token_freshness.append(token_payload['data_freshness_ts'])
        except (urllib.error.URLError, TimeoutError, OSError, SchemaError, KeyError, TypeError, ValueError):
            token_ok = False
        cursor = chunk_end + dt.timedelta(days=1)
    history = {'series': [s for h in histories for s in h['series']], 'data': [r for h in histories for r in h['data']],
               'data_freshness_ts': min((h['data_freshness_ts'] for h in histories if h.get('data_freshness_ts')), default=None)}
    total = sum(amount(item['total']) for item in history['series'])
    estimate = request('/wham/usage/credits/estimate', body={'credits': round(total, 6)})
    result = normalize(history, estimate, start, end)
    day_estimate = estimate if days == 1 else request("/wham/usage/credits/estimate", body={"credits": round(result["todayCredits"], 6)})
    result["dayEstimatedUSD"] = amount(day_estimate["estimated_usage_usd_micros"]) / 1_000_000
    result["rangeStart"] = str(start)
    result["rangeEnd"] = str(end)
    result["reportedDays"] = [row["date"] for row in history["data"]]
    credit_rows = {row['date']: row['values'] for row in history['data']}
    # Check the source's conversion before attributing estimated dollars to models.
    one = request('/wham/usage/credits/estimate', body={'credits': 1})
    rate = amount(one['estimated_usage_usd_micros']) / 1_000_000
    linear = math.isclose(total * rate, result['estimatedUSD'], rel_tol=1e-6, abs_tol=0.01)
    for row in result['daily']:
        values = credit_rows.get(row['date'], {})
        row['models'] = {str(k): amount(v) for k, v in values.items()}
        row['tokens'] = tokens_by_day.get(row['date'], {}) if token_ok else None
        row['estimatedUSD'] = row['credits'] * rate if linear else None
    result['usdPerCredit'] = rate if linear else None
    result['tokensAvailable'] = token_ok
    result['tokenDataAsOf'] = min(token_freshness, default=None)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--end", type=dt.date.fromisoformat)
    parser.add_argument("--days", type=int, default=30)
    args = parser.parse_args()
    try:
        result = collect(args.end, args.days)
    except FileNotFoundError:
        result = {'state': 'auth', 'message': 'Codex sign-in is unavailable. Sign in to Codex and refresh.'}
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            message = 'Sign-in expired or access unavailable. Open Codex, sign in, then refresh.'
        elif exc.code == 429:
            message = 'OpenAI requested a pause. Usage will retry on the next refresh.'
        else:
            message = 'OpenAI usage is temporarily unavailable (HTTP %d).' % exc.code
        result = {'state': 'error', 'message': message}
    except (urllib.error.URLError, TimeoutError, OSError):
        result = {'state': 'error', 'message': 'Cannot reach usage data. Check your connection and refresh.'}
    except Exception:
        # Never echo exceptions or response bodies: they can contain secrets.
        result = {'state': 'error', 'message': 'Usage response changed or could not be read. Update the collector.'}
    result['fetchedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    print(json.dumps(result, allow_nan=False))

if __name__ == '__main__':
    main()
