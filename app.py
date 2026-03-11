import os
import requests
from flask import Flask, request, Response, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

EDGAR_URL = 'https://efts.sec.gov/LATEST/search-index'
HEADERS = {
    'User-Agent': 'SEC EDGAR Research Tool (personal use) contact@example.com',
    'Accept': 'application/json',
}


@app.route('/search')
def search():
    params = dict(request.args)
    try:
        resp = requests.get(EDGAR_URL, params=params, headers=HEADERS, timeout=15)
        return Response(resp.content, status=resp.status_code, mimetype='application/json')
    except requests.RequestException as e:
        return jsonify({'error': str(e)}), 502


@app.route('/health')
def health():
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
