// Teste do build Web (M0): sobe scripts/serve-web.py, abre game.tscn no Chromium (Playwright, WebGL por CPU), deixa rodar e
// falha em erro no console ou se o canvas ficar em branco. Uso: scripts/export-web.sh && node tests/web.js
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');
const PORT = 8061, WEB = path.join(__dirname, '../build/web/');
const html = fs.readFileSync(WEB + 'index.html', 'utf8');
fs.writeFileSync(WEB + 'test.html', html);
(async () => {
	const srv = spawn('python3', [path.join(__dirname, '../scripts/serve-web.py'), String(PORT)], { stdio: 'inherit' });
	await new Promise(r => setTimeout(r, 800));
	const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	const errors = [], logs = [];
	page.on('console', m => { logs.push(m.type() + ': ' + m.text()); if (m.type() === 'error') errors.push(m.text()); });
	page.on('pageerror', e => errors.push('pageerror: ' + e.message));
	let shot;
	try {
		await page.goto(`http://127.0.0.1:${PORT}/test.html`);
		await page.waitForTimeout(25000);   // baixa o .pck e monta o menu (o mundo do fundo gera em wasm)
		const click = async (x, y, ms = 2500) => { await page.mouse.click(x, y); await page.waitForTimeout(ms); };
		await click(640, 435);                                   // Um Jogador
		await click(1090, 580);                                  // Novo personagem
		await click(800, 355, 800); await page.keyboard.type('Robo'); await page.keyboard.press('Enter'); await page.waitForTimeout(2500);
		await click(708, 347, 3000);                             // Jogar com ele
		await click(936, 580);                                   // Novo mundo
		await click(800, 381, 800); await page.keyboard.type('Mundo'); await page.keyboard.press('Enter'); await page.waitForTimeout(4000);   // cria e volta à lista (user:// = IndexedDB)
		await page.waitForTimeout(3000);                         // deixa o IndexedDB gravar
		await page.reload(); await page.waitForTimeout(25000);   // user:// sobrevive ao recarregar? (personagem e mundo têm de estar na lista)
		await click(640, 435); await click(708, 347, 3000);      // Um Jogador → Jogar com o personagem salvo
		await click(708, 347, 1000);                             // Jogar no mundo salvo
		for (let i = 0; i < Number(process.env.WAIT || 8); i++) { await page.waitForTimeout(10000); shot = await page.screenshot({ path: path.join(__dirname, `../textures/web_${i}.png`) }); }
		await page.evaluate(() => { window.__vivo = 1; });
		await page.keyboard.press('F5'); await page.waitForTimeout(1500);   // F5 salva no jogo: a página não pode recarregar
		if (!(await page.evaluate(() => window.__vivo === 1))) errors.push('F5 recarregou a página');
		await page.mouse.click(640, 360); await page.waitForTimeout(800);   // o clique recaptura o ponteiro
		console.log('ponteiro preso:', await page.evaluate(() => !!document.pointerLockElement));
		await page.evaluate(() => document.exitPointerLock()); await page.waitForTimeout(1500);   // o que o Esc do browser faz
		shot = await page.screenshot({ path: path.join(__dirname, '../textures/web_esc.png') });   // inventário tem de estar aberto (arquivo conferido à mão)
	} finally { await browser.close(); srv.kill(); fs.unlinkSync(WEB + 'test.html'); }
	console.log(logs.slice(-12).join('\n'));
	if (shot.length < 30000) errors.push('canvas em branco (PNG de ' + shot.length + ' bytes)');   // quadro liso comprime a quase nada
	if (errors.length) console.log('FALHA:\n' + errors.join('\n'));
	else console.log('ok: build Web rodou sem erro (PNG de ' + shot.length + ' bytes)');
	process.exit(errors.length ? 1 : 0);
})();
