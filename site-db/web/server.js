const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());
app.use(express.static('public'));

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT) || 5432,
  user: process.env.DB_USER || 'app',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'recados',
});

// Cria a tabela; tenta várias vezes caso o banco ainda esteja subindo
async function iniciarBanco() {
  for (let tentativa = 1; tentativa <= 20; tentativa++) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS recados (
          id SERIAL PRIMARY KEY,
          nome VARCHAR(60) NOT NULL,
          mensagem VARCHAR(280) NOT NULL,
          criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);
      console.log('Banco de dados pronto');
      return;
    } catch (err) {
      console.log(`Aguardando o banco (${tentativa}/20): ${err.message}`);
      await new Promise((resolve) => setTimeout(resolve, 3000));
    }
  }
  throw new Error('Banco de dados indisponível');
}

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', banco: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'erro', banco: 'indisponivel' });
  }
});

app.get('/api/recados', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, nome, mensagem, criado_em FROM recados ORDER BY id DESC LIMIT 50'
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao buscar os recados' });
  }
});

app.post('/api/recados', async (req, res) => {
  const nome = String(req.body.nome || '').trim();
  const mensagem = String(req.body.mensagem || '').trim();

  if (!nome || !mensagem) {
    return res.status(400).json({ erro: 'Preencha nome e mensagem' });
  }
  if (nome.length > 60 || mensagem.length > 280) {
    return res.status(400).json({ erro: 'Texto muito longo' });
  }

  try {
    const { rows } = await pool.query(
      'INSERT INTO recados (nome, mensagem) VALUES ($1, $2) RETURNING id, nome, mensagem, criado_em',
      [nome, mensagem]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao salvar o recado' });
  }
});

const PORT = 3000;

iniciarBanco()
  .then(() => {
    app.listen(PORT, () => console.log(`Servidor rodando na porta ${PORT}`));
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
