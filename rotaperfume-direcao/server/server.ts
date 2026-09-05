import { createApp, analytics, genie, server, getExecutionContext } from '@databricks/appkit';
import { z, flattenError } from 'zod';

const retornoSchema = z.object({
  cliente_id: z.coerce.number().int(),
  vendedor: z.string().min(1),
  status: z.enum(['vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu']),
  comentario: z.string().max(500).optional(),
  referencia: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

createApp({
  plugins: [analytics(), genie(), server()],
  // A fila muda a cada retorno registrado — sem cache global, para que o
  // remount da tabela (via key) sempre busque o dado mais recente.
  cache: { enabled: false },
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // O Databricks Apps injeta o e-mail de quem está logado nesse header.
      // Em desenvolvimento local (npm run dev) o header não existe.
      app.get('/api/quem-sou', (req, res) => {
        const email = req.header('x-forwarded-email') ?? 'dev-local@rotaperfume.com';
        res.json({ email });
      });

      app.post('/api/retorno', async (req, res) => {
        const parsed = retornoSchema.safeParse(req.body);
        if (!parsed.success) {
          res.status(400).json({
            error: 'Dados inválidos.',
            status_aceitos: retornoSchema.shape.status.options,
            detalhes: flattenError(parsed.error),
          });
          return;
        }

        const { cliente_id, vendedor, status, comentario, referencia } = parsed.data;
        const registradoPor = req.header('x-forwarded-email') ?? 'dev-local@rotaperfume.com';

        const context = getExecutionContext();
        const warehouseId = await context.warehouseId;
        if (!warehouseId) {
          res.status(500).json({ error: 'Warehouse não configurado.' });
          return;
        }

        try {
          const response = await context.client.statementExecution.executeStatement({
            warehouse_id: warehouseId,
            statement: `
              INSERT INTO lakehouse_rotaperfume.gold.retorno_ligacao
                (cliente_id, vendedor, status, comentario, registrado_em, registrado_por, _referencia)
              VALUES
                (:cliente_id, :vendedor, :status, :comentario, current_timestamp(), :registrado_por, :referencia)
            `,
            parameters: [
              { name: 'cliente_id', type: 'INT', value: String(cliente_id) },
              { name: 'vendedor', type: 'STRING', value: vendedor },
              { name: 'status', type: 'STRING', value: status },
              { name: 'comentario', type: 'STRING', ...(comentario ? { value: comentario } : {}) },
              { name: 'registrado_por', type: 'STRING', value: registradoPor },
              { name: 'referencia', type: 'DATE', value: referencia },
            ],
            wait_timeout: '30s',
          });

          if (response.status?.state !== 'SUCCEEDED') {
            throw new Error(response.status?.error?.message ?? 'Falha ao gravar o retorno.');
          }

          res.json({ ok: true });
        } catch (err) {
          res.status(500).json({ error: err instanceof Error ? err.message : 'Falha ao gravar o retorno.' });
        }
      });
    });
  },
}).catch(console.error);
