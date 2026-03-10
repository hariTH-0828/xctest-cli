import Foundation

/// Embedded HTML/CSS/JS dashboard served as a single page.
/// All assets are inlined so the CLI is a single binary with no external dependencies.
enum DashboardHTML {

    static let indexHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>xctest-cli — Test Dashboard</title>
        <style>\(css)</style>
    </head>
    <body>
        <div class="container">
            <header>
                <h1>xctest-cli</h1>
                <p class="subtitle">Test Results Dashboard</p>
                <p class="timestamp" id="timestamp"></p>
            </header>

            <div class="live-banner hidden" id="live-banner">
                <div class="live-dot"></div>
                <span class="live-phase" id="live-phase">Preparing...</span>
                <span class="live-current" id="live-current"></span>
                <span class="live-stats" id="live-stats"></span>
                <span class="live-elapsed" id="live-elapsed"></span>
            </div>

            <div class="summary-cards" id="summary-cards">
                <div class="card card-total">
                    <div class="card-value" id="total-count">—</div>
                    <div class="card-label">Total Tests</div>
                </div>
                <div class="card card-passed">
                    <div class="card-value" id="passed-count">—</div>
                    <div class="card-label">Passed</div>
                </div>
                <div class="card card-failed">
                    <div class="card-value" id="failed-count">—</div>
                    <div class="card-label">Failed</div>
                </div>
                <div class="card card-skipped">
                    <div class="card-value" id="skipped-count">—</div>
                    <div class="card-label">Skipped</div>
                </div>
                <div class="card card-duration">
                    <div class="card-value" id="duration-value">—</div>
                    <div class="card-label">Duration</div>
                </div>
            </div>

            <div class="progress-bar-container">
                <div class="progress-bar" id="progress-bar">
                    <div class="progress-passed" id="progress-passed"></div>
                    <div class="progress-failed" id="progress-failed"></div>
                    <div class="progress-skipped" id="progress-skipped"></div>
                </div>
            </div>

            <div class="controls">
                <div class="filters">
                    <button class="filter-btn active" data-filter="all">All</button>
                    <button class="filter-btn" data-filter="passed">Passed</button>
                    <button class="filter-btn" data-filter="failed">Failed</button>
                    <button class="filter-btn" data-filter="skipped">Skipped</button>
                </div>
                <div class="search-box">
                    <input type="text" id="search-input" placeholder="Search tests...">
                </div>
                <button class="download-btn" id="download-btn" title="Download JSON report">
                    ⬇ Download Report
                </button>
            </div>

            <div class="test-suites" id="test-suites">
                <p class="loading">Loading test results...</p>
            </div>

            <div class="failure-panel hidden" id="failure-panel">
                <div class="failure-panel-header">
                    <h3>Failure Details</h3>
                    <button class="close-btn" id="close-panel">&times;</button>
                </div>
                <div class="failure-panel-body" id="failure-panel-body"></div>
            </div>
        </div>

        <script>\(javascript)</script>
    </body>
    </html>
    """

    static let css: String = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
        background: #0d1117;
        color: #c9d1d9;
        line-height: 1.6;
    }
    .container {
        max-width: 1200px;
        margin: 0 auto;
        padding: 24px;
    }
    header {
        text-align: center;
        margin-bottom: 32px;
    }
    header h1 {
        font-size: 28px;
        font-weight: 700;
        color: #f0f6fc;
        letter-spacing: -0.5px;
    }
    .subtitle {
        color: #8b949e;
        font-size: 14px;
        margin-top: 4px;
    }
    .timestamp {
        color: #6e7681;
        font-size: 12px;
        margin-top: 8px;
    }

    /* Summary Cards */
    .summary-cards {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
        gap: 16px;
        margin-bottom: 24px;
    }
    .card {
        background: #161b22;
        border: 1px solid #30363d;
        border-radius: 12px;
        padding: 20px;
        text-align: center;
        transition: transform 0.15s;
    }
    .card:hover { transform: translateY(-2px); }
    .card-value {
        font-size: 36px;
        font-weight: 700;
        line-height: 1.2;
    }
    .card-label {
        font-size: 13px;
        color: #8b949e;
        margin-top: 4px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    .card-total .card-value { color: #58a6ff; }
    .card-passed .card-value { color: #3fb950; }
    .card-failed .card-value { color: #f85149; }
    .card-skipped .card-value { color: #d29922; }
    .card-duration .card-value { color: #bc8cff; font-size: 24px; }

    /* Progress Bar */
    .progress-bar-container { margin-bottom: 24px; }
    .progress-bar {
        display: flex;
        height: 8px;
        border-radius: 4px;
        overflow: hidden;
        background: #21262d;
    }
    .progress-passed { background: #3fb950; transition: width 0.5s; }
    .progress-failed { background: #f85149; transition: width 0.5s; }
    .progress-skipped { background: #d29922; transition: width 0.5s; }

    /* Controls */
    .controls {
        display: flex;
        align-items: center;
        gap: 16px;
        margin-bottom: 24px;
        flex-wrap: wrap;
    }
    .filters { display: flex; gap: 8px; }
    .filter-btn {
        background: #21262d;
        border: 1px solid #30363d;
        color: #c9d1d9;
        padding: 6px 16px;
        border-radius: 20px;
        cursor: pointer;
        font-size: 13px;
        transition: all 0.15s;
    }
    .filter-btn:hover { border-color: #58a6ff; color: #58a6ff; }
    .filter-btn.active { background: #58a6ff; color: #0d1117; border-color: #58a6ff; }
    .search-box { flex: 1; min-width: 200px; }
    .search-box input {
        width: 100%;
        padding: 8px 16px;
        background: #0d1117;
        border: 1px solid #30363d;
        border-radius: 8px;
        color: #c9d1d9;
        font-size: 14px;
        outline: none;
    }
    .search-box input:focus { border-color: #58a6ff; }
    .search-box input::placeholder { color: #484f58; }
    .download-btn {
        background: #21262d;
        border: 1px solid #30363d;
        color: #c9d1d9;
        padding: 8px 16px;
        border-radius: 8px;
        cursor: pointer;
        font-size: 13px;
        white-space: nowrap;
    }
    .download-btn:hover { border-color: #58a6ff; color: #58a6ff; }

    /* Test Suites */
    .test-suite {
        background: #161b22;
        border: 1px solid #30363d;
        border-radius: 12px;
        margin-bottom: 16px;
        overflow: hidden;
    }
    .suite-header {
        padding: 16px 20px;
        font-weight: 600;
        font-size: 15px;
        cursor: pointer;
        display: flex;
        justify-content: space-between;
        align-items: center;
        user-select: none;
        border-bottom: 1px solid #30363d;
    }
    .suite-header:hover { background: #1c2128; }
    .suite-header .suite-name { display: flex; align-items: center; gap: 8px; }
    .suite-header .chevron {
        transition: transform 0.2s;
        color: #484f58;
    }
    .suite-header.collapsed .chevron { transform: rotate(-90deg); }
    .suite-stats {
        display: flex;
        gap: 12px;
        font-size: 12px;
        font-weight: 400;
    }
    .suite-stats .stat-passed { color: #3fb950; }
    .suite-stats .stat-failed { color: #f85149; }
    .suite-stats .stat-skipped { color: #d29922; }

    .test-list { padding: 0; }
    .test-list.collapsed { display: none; }
    .test-row {
        display: flex;
        align-items: center;
        padding: 10px 20px;
        border-bottom: 1px solid #21262d;
        font-size: 14px;
        transition: background 0.1s;
        cursor: default;
    }
    .test-row:last-child { border-bottom: none; }
    .test-row:hover { background: #1c2128; }
    .test-row.failed { cursor: pointer; }
    .test-row.failed:hover { background: #1f1215; }

    .status-icon {
        width: 20px;
        height: 20px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        margin-right: 12px;
        flex-shrink: 0;
    }
    .status-passed { background: #0e3a1e; color: #3fb950; }
    .status-failed { background: #3d1117; color: #f85149; }
    .status-skipped { background: #2e2111; color: #d29922; }

    .test-name { flex: 1; font-family: 'SF Mono', Menlo, monospace; font-size: 13px; }
    .test-duration { color: #484f58; font-size: 12px; margin-left: 12px; }
    .test-failure-hint {
        color: #f85149;
        font-size: 12px;
        margin-left: 12px;
        max-width: 300px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    /* Failure Panel */
    .failure-panel {
        position: fixed;
        bottom: 0;
        left: 0;
        right: 0;
        background: #161b22;
        border-top: 2px solid #f85149;
        padding: 0;
        max-height: 40vh;
        overflow-y: auto;
        z-index: 100;
        box-shadow: 0 -4px 24px rgba(0,0,0,0.5);
    }
    .failure-panel.hidden { display: none; }
    .failure-panel-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 12px 24px;
        border-bottom: 1px solid #30363d;
        position: sticky;
        top: 0;
        background: #161b22;
    }
    .failure-panel-header h3 { color: #f85149; font-size: 14px; }
    .close-btn {
        background: none;
        border: none;
        color: #8b949e;
        font-size: 20px;
        cursor: pointer;
    }
    .close-btn:hover { color: #f0f6fc; }
    .failure-panel-body { padding: 16px 24px; }
    .failure-detail { margin-bottom: 12px; }
    .failure-detail label {
        display: block;
        font-size: 11px;
        color: #8b949e;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        margin-bottom: 4px;
    }
    .failure-detail .value {
        font-family: 'SF Mono', Menlo, monospace;
        font-size: 13px;
        color: #f0f6fc;
        background: #0d1117;
        padding: 8px 12px;
        border-radius: 6px;
        white-space: pre-wrap;
        word-break: break-word;
    }

    .loading {
        text-align: center;
        color: #8b949e;
        padding: 48px;
    }
    .no-results {
        text-align: center;
        color: #484f58;
        padding: 32px;
        font-size: 14px;
    }

    .live-banner {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 20px;
        background: linear-gradient(135deg, #1a1e2e, #161b22);
        border: 1px solid #1f6feb44;
        border-radius: 12px;
        margin-bottom: 20px;
        font-size: 14px;
        animation: liveFadeIn 0.3s ease;
    }
    .live-banner.hidden { display: none; }
    @keyframes liveFadeIn { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: translateY(0); } }
    .live-dot {
        width: 10px; height: 10px;
        border-radius: 50%;
        background: #3fb950;
        animation: livePulse 1.5s ease-in-out infinite;
        flex-shrink: 0;
    }
    .live-dot.building { background: #d29922; }
    .live-dot.done { background: #8b949e; animation: none; }
    @keyframes livePulse { 0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(63,185,80,0.4); } 50% { opacity: 0.7; box-shadow: 0 0 0 6px rgba(63,185,80,0); } }
    .live-phase { color: #58a6ff; font-weight: 600; }
    .live-current { color: #8b949e; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .live-stats { color: #c9d1d9; white-space: nowrap; }
    .live-elapsed { color: #484f58; white-space: nowrap; }

    @media (max-width: 768px) {
        .controls { flex-direction: column; align-items: stretch; }
        .filters { justify-content: center; }
        .test-failure-hint { display: none; }
    }
    """

    static let javascript: String = """
    (function() {
        let reportData = null;
        let liveData = null;
        let isLive = false;
        let currentFilter = 'all';
        let searchQuery = '';

        // Format seconds → "1m 23s"
        function formatElapsed(s) {
            const m = Math.floor(s / 60);
            const sec = Math.floor(s % 60);
            return m > 0 ? m + 'm ' + sec + 's' : sec + 's';
        }

        async function pollLive() {
            try {
                const res = await fetch('/api/live');
                if (!res.ok) return;
                liveData = await res.json();

                const banner = document.getElementById('live-banner');
                const dot = banner.querySelector('.live-dot');
                const phase = document.getElementById('live-phase');
                const current = document.getElementById('live-current');
                const stats = document.getElementById('live-stats');
                const elapsed = document.getElementById('live-elapsed');

                if (liveData.phase === 'idle') {
                    banner.classList.add('hidden');
                    isLive = false;
                    return;
                }

                isLive = true;
                banner.classList.remove('hidden');
                dot.className = 'live-dot';

                if (liveData.phase === 'building') {
                    phase.textContent = '🔨 Building...';
                    dot.classList.add('building');
                    current.textContent = '';
                    stats.textContent = '';
                } else if (liveData.phase === 'testing') {
                    phase.textContent = '🧪 Testing';
                    current.textContent = liveData.currentTest ? '→ ' + liveData.currentTest : '';
                    stats.textContent = '✅ ' + liveData.passed + '  ❌ ' + liveData.failed + '  📊 ' + liveData.totalCompleted;
                } else if (liveData.phase === 'done') {
                    phase.textContent = '🏁 Done';
                    dot.classList.add('done');
                    current.textContent = '';
                    stats.textContent = '✅ ' + liveData.passed + '  ❌ ' + liveData.failed + '  📊 ' + liveData.totalCompleted;
                    // Load final report
                    setTimeout(loadReport, 500);
                }

                elapsed.textContent = '[' + formatElapsed(liveData.elapsed) + ']';

                // Build a live report from live data to show in the dashboard
                if (liveData.phase === 'testing' || (liveData.phase === 'done' && !reportData)) {
                    renderLiveTests();
                }
            } catch(e) { /* ignore */ }
        }

        function renderLiveTests() {
            if (!liveData || !liveData.testCases || liveData.testCases.length === 0) return;

            // Group by suite
            const suiteMap = {};
            for (const tc of liveData.testCases) {
                const sn = tc.suiteName || 'Tests';
                if (!suiteMap[sn]) suiteMap[sn] = [];
                suiteMap[sn].push(tc);
            }

            const liveSuites = Object.entries(suiteMap).map(([name, cases]) => ({ name, testCases: cases }));
            const total = liveData.totalCompleted;
            const summary = {
                totalTests: total,
                passed: liveData.passed,
                failed: liveData.failed,
                skipped: liveData.skipped,
                duration: formatElapsed(liveData.elapsed)
            };

            // Update summary cards
            document.getElementById('total-count').textContent = summary.totalTests;
            document.getElementById('passed-count').textContent = summary.passed;
            document.getElementById('failed-count').textContent = summary.failed;
            document.getElementById('skipped-count').textContent = summary.skipped;
            document.getElementById('duration-value').textContent = summary.duration;
            document.getElementById('timestamp').textContent = 'Live — ' + liveData.scheme;

            const t = total || 1;
            document.getElementById('progress-passed').style.width = (summary.passed / t * 100) + '%';
            document.getElementById('progress-failed').style.width = (summary.failed / t * 100) + '%';
            document.getElementById('progress-skipped').style.width = (summary.skipped / t * 100) + '%';

            // Render test suites
            const container = document.getElementById('test-suites');
            let html = '';
            for (const suite of liveSuites) {
                const filtered = suite.testCases.filter(tc => {
                    if (currentFilter !== 'all' && tc.status !== currentFilter) return false;
                    if (searchQuery) {
                        const q = searchQuery.toLowerCase();
                        return tc.name.toLowerCase().includes(q);
                    }
                    return true;
                });
                if (filtered.length === 0) continue;

                const passed = filtered.filter(t => t.status === 'passed').length;
                const failed = filtered.filter(t => t.status === 'failed').length;

                html += '<div class="test-suite">';
                html += '<div class="suite-header" onclick="toggleSuite(this)">';
                html += '<span class="suite-name"><span class="chevron">▼</span> ' + escapeHtml(suite.name) + '</span>';
                html += '<span class="suite-stats">';
                if (passed) html += '<span class="stat-passed">' + passed + ' passed</span>';
                if (failed) html += '<span class="stat-failed">' + failed + ' failed</span>';
                html += '</span></div>';
                html += '<div class="test-list">';

                for (const tc of filtered) {
                    const statusClass = 'status-' + tc.status;
                    const icon = tc.status === 'passed' ? '✓' : tc.status === 'failed' ? '✗' : '⊘';
                    html += '<div class="test-row">';
                    html += '<span class="status-icon ' + statusClass + '">' + icon + '</span>';
                    html += '<span class="test-name">' + escapeHtml(tc.name) + '</span>';
                    if (tc.duration !== undefined) {
                        html += '<span class="test-duration">' + tc.duration.toFixed(3) + 's</span>';
                    }
                    html += '</div>';
                }

                html += '</div></div>';
            }

            if (liveData.currentTest) {
                html += '<div class="test-suite">';
                html += '<div class="suite-header">';
                html += '<span class="suite-name">⏳ Running</span></div>';
                html += '<div class="test-list">';
                html += '<div class="test-row"><span class="status-icon" style="color:#d29922;">●</span>';
                html += '<span class="test-name">' + escapeHtml(liveData.currentTest) + '</span>';
                html += '<span class="test-duration" style="color:#d29922;">running...</span></div>';
                html += '</div></div>';
            }

            if (html) container.innerHTML = html;
        }

        async function loadReport() {
            try {
                const res = await fetch('/api/report');
                if (!res.ok) throw new Error('Failed to load report');
                reportData = await res.json();
                render();
            } catch (e) {
                document.getElementById('test-suites').innerHTML =
                    '<p class="loading">Failed to load test results. Ensure the server is running.</p>';
            }
        }

        function render() {
            if (!reportData) return;
            const s = reportData.summary;

            document.getElementById('total-count').textContent = s.totalTests;
            document.getElementById('passed-count').textContent = s.passed;
            document.getElementById('failed-count').textContent = s.failed;
            document.getElementById('skipped-count').textContent = s.skipped;
            document.getElementById('duration-value').textContent = s.duration;
            document.getElementById('timestamp').textContent =
                'Generated: ' + new Date(reportData.generatedAt).toLocaleString();

            const total = s.totalTests || 1;
            document.getElementById('progress-passed').style.width = (s.passed / total * 100) + '%';
            document.getElementById('progress-failed').style.width = (s.failed / total * 100) + '%';
            document.getElementById('progress-skipped').style.width = (s.skipped / total * 100) + '%';

            renderSuites();
        }

        function renderSuites() {
            const container = document.getElementById('test-suites');
            const suites = reportData.testSuites;
            let html = '';

            for (const suite of suites) {
                const filtered = suite.testCases.filter(tc => {
                    if (currentFilter !== 'all' && tc.status !== currentFilter) return false;
                    if (searchQuery) {
                        const q = searchQuery.toLowerCase();
                        return tc.name.toLowerCase().includes(q) ||
                               tc.suiteName.toLowerCase().includes(q) ||
                               (tc.failureMessage && tc.failureMessage.toLowerCase().includes(q));
                    }
                    return true;
                });

                if (filtered.length === 0) continue;

                const passed = filtered.filter(t => t.status === 'passed').length;
                const failed = filtered.filter(t => t.status === 'failed').length;
                const skipped = filtered.filter(t => t.status === 'skipped').length;

                html += '<div class="test-suite">';
                html += '<div class="suite-header" onclick="toggleSuite(this)">';
                html += '<span class="suite-name"><span class="chevron">▼</span> ' + escapeHtml(suite.name) + '</span>';
                html += '<span class="suite-stats">';
                if (passed) html += '<span class="stat-passed">' + passed + ' passed</span>';
                if (failed) html += '<span class="stat-failed">' + failed + ' failed</span>';
                if (skipped) html += '<span class="stat-skipped">' + skipped + ' skipped</span>';
                html += '</span></div>';
                html += '<div class="test-list">';

                for (const tc of filtered) {
                    const statusClass = 'status-' + tc.status;
                    const icon = tc.status === 'passed' ? '✓' : tc.status === 'failed' ? '✗' : '⊘';
                    const rowClass = tc.status === 'failed' ? ' failed' : '';
                    const onclick = tc.status === 'failed' ?
                        ' onclick="showFailure(' + JSON.stringify(JSON.stringify(tc)).slice(0) + ')"' : '';

                    html += '<div class="test-row' + rowClass + '"' + onclick + '>';
                    html += '<span class="status-icon ' + statusClass + '">' + icon + '</span>';
                    html += '<span class="test-name">' + escapeHtml(tc.name) + '</span>';
                    if (tc.duration !== undefined) {
                        html += '<span class="test-duration">' + tc.duration.toFixed(3) + 's</span>';
                    }
                    if (tc.failureMessage) {
                        html += '<span class="test-failure-hint">' + escapeHtml(tc.failureMessage) + '</span>';
                    }
                    html += '</div>';
                }

                html += '</div></div>';
            }

            if (!html) {
                html = '<p class="no-results">No tests match the current filter.</p>';
            }

            container.innerHTML = html;
        }

        function escapeHtml(str) {
            const div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }

        window.toggleSuite = function(header) {
            header.classList.toggle('collapsed');
            header.nextElementSibling.classList.toggle('collapsed');
        };

        window.showFailure = function(tcJson) {
            const tc = JSON.parse(tcJson);
            const panel = document.getElementById('failure-panel');
            const body = document.getElementById('failure-panel-body');

            let html = '';
            html += '<div class="failure-detail"><label>Test Name</label>';
            html += '<div class="value">' + escapeHtml(tc.suiteName + '.' + tc.name) + '</div></div>';

            if (tc.failureMessage) {
                html += '<div class="failure-detail"><label>Failure</label>';
                html += '<div class="value">' + escapeHtml(tc.failureMessage) + '</div></div>';
            }
            if (tc.file) {
                html += '<div class="failure-detail"><label>File</label>';
                html += '<div class="value">' + escapeHtml(tc.file) + '</div></div>';
            }
            if (tc.line) {
                html += '<div class="failure-detail"><label>Line</label>';
                html += '<div class="value">' + tc.line + '</div></div>';
            }

            body.innerHTML = html;
            panel.classList.remove('hidden');
        };

        document.getElementById('close-panel').addEventListener('click', function() {
            document.getElementById('failure-panel').classList.add('hidden');
        });

        document.querySelectorAll('.filter-btn').forEach(function(btn) {
            btn.addEventListener('click', function() {
                document.querySelectorAll('.filter-btn').forEach(function(b) {
                    b.classList.remove('active');
                });
                btn.classList.add('active');
                currentFilter = btn.dataset.filter;
                renderSuites();
            });
        });

        document.getElementById('search-input').addEventListener('input', function(e) {
            searchQuery = e.target.value;
            renderSuites();
        });

        document.getElementById('download-btn').addEventListener('click', function() {
            if (!reportData) return;
            const blob = new Blob([JSON.stringify(reportData, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'test-report.json';
            a.click();
            URL.revokeObjectURL(url);
        });

        // Poll live status every 2 seconds
        setInterval(pollLive, 2000);
        // Refresh final report every 10 seconds
        setInterval(function() { if (!isLive) loadReport(); }, 10000);
        // Initial load
        pollLive();
        loadReport();
    })();
    """
}
