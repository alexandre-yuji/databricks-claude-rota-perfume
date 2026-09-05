import { useState, useMemo } from 'react';
import {
  useAnalyticsQuery,
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
  Label,
  Badge,
  Button,
  Input,
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@databricks/appkit-ui/react';
import { sql } from '@databricks/appkit-ui/js';
import { Users } from 'lucide-react';
import { formatBRL, formatInt, formatScorePercent, formatPercent1, formatDateBR } from '../../utils/formatters';

const emptyParams = {};

const STATUS_OPTIONS = [
  { status: 'vendeu', label: 'Vendeu', variant: 'default' as const },
  { status: 'vai_pensar', label: 'Vai pensar', variant: 'secondary' as const },
  { status: 'sem_interesse', label: 'Sem interesse', variant: 'outline' as const },
  { status: 'nao_atendeu', label: 'Não atendeu', variant: 'outline' as const },
];

function faixaVariant(faixa: string): 'default' | 'secondary' | 'outline' {
  if (faixa === 'Muito quente' || faixa === 'Quente') return 'default';
  if (faixa === 'Morna') return 'secondary';
  return 'outline';
}

function statusLabel(status: string): string {
  return STATUS_OPTIONS.find((o) => o.status === status)?.label ?? status;
}

function statusVariant(status: string): 'default' | 'secondary' | 'outline' {
  return STATUS_OPTIONS.find((o) => o.status === status)?.variant ?? 'outline';
}

interface RetornoCellProps {
  clienteId: number;
  vendedor: string;
  referencia: string;
  retornoStatus: string | null;
  retornoComentario: string | null;
  onSaved: () => void;
}

function RetornoCell({ clienteId, vendedor, referencia, retornoStatus, retornoComentario, onSaved }: RetornoCellProps) {
  const [comentario, setComentario] = useState('');
  const [saving, setSaving] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  if (retornoStatus) {
    return (
      <div className="space-y-1">
        <Badge variant={statusVariant(retornoStatus)}>{statusLabel(retornoStatus)}</Badge>
        {retornoComentario && <div className="text-xs text-muted-foreground">{retornoComentario}</div>}
      </div>
    );
  }

  async function registrar(status: string) {
    setSaving(true);
    setErro(null);
    try {
      const resp = await fetch('/api/retorno', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          cliente_id: clienteId,
          vendedor,
          status,
          comentario: comentario.trim() || undefined,
          referencia,
        }),
      });
      if (!resp.ok) {
        const body = await resp.json().catch(() => ({}));
        throw new Error(body.error ?? 'Falha ao gravar o retorno.');
      }
      onSaved();
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'Falha ao gravar o retorno.');
      setSaving(false);
    }
  }

  return (
    <div className="space-y-2 min-w-[240px]">
      <Input
        placeholder="Comentário (opcional)"
        value={comentario}
        onChange={(e) => setComentario(e.target.value)}
        disabled={saving}
        maxLength={500}
        className="h-8 text-xs"
      />
      <div className="flex flex-wrap gap-1">
        {STATUS_OPTIONS.map((o) => (
          <Button
            key={o.status}
            size="sm"
            variant={o.variant}
            disabled={saving}
            onClick={() => registrar(o.status)}
          >
            {o.label}
          </Button>
        ))}
      </div>
      {erro && (
        <Alert variant="destructive" className="py-1.5 px-2">
          <AlertDescription className="text-xs">{erro}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}

interface DataSectionProps {
  vendedor: string;
  onSaved: () => void;
}

function DataSection({ vendedor, onSaved }: DataSectionProps) {
  const kpis = useAnalyticsQuery('kpis_semana', emptyParams);
  const filaParams = useMemo(() => ({ vendedor: sql.string(vendedor) }), [vendedor]);
  const fila = useAnalyticsQuery('fila', filaParams);

  const kpiRow = kpis.data?.[0];

  return (
    <>
      <div>
        {kpiRow && (
          <p className="text-sm text-muted-foreground mt-1">
            Referência {formatDateBR(kpiRow.referencia)} · modelo versão {kpiRow.versao}
          </p>
        )}
      </div>

      {kpis.loading && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-28 w-full" />
          ))}
        </div>
      )}
      {kpis.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível carregar os números da semana</AlertTitle>
          <AlertDescription>{kpis.error}</AlertDescription>
        </Alert>
      )}
      {kpiRow && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-sm text-muted-foreground">Contatos da semana</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{formatInt(kpiRow.contatos)}</div>
              <div className="text-xs text-muted-foreground mt-1">{formatInt(kpiRow.vendedores)} vendedores</div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-sm text-muted-foreground">Receita esperada</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{formatBRL(kpiRow.receita_esperada)}</div>
              <div className="text-xs text-muted-foreground mt-1">estimativa, não realizada</div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-sm text-muted-foreground">Conversão prevista</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">
                {formatPercent1((Number(kpiRow.acertos_top200) / Number(kpiRow.contatos)) * 100)}
              </div>
              <div className="text-xs text-muted-foreground mt-1">
                vs {formatPercent1(Number(kpiRow.taxa_base) * 100)} ligando às cegas
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-sm text-muted-foreground">Já trabalhados</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{formatInt(kpiRow.ja_trabalhados)}</div>
              <div className="text-xs text-muted-foreground mt-1">{formatInt(kpiRow.viraram_pedido)} viraram pedido</div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Fila de contatos</CardTitle>
          <CardDescription>Ordenada por prioridade dentro de cada vendedor.</CardDescription>
        </CardHeader>
        <CardContent>
          {fila.loading && (
            <div className="space-y-2">
              {[0, 1, 2, 3, 4].map((i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          )}
          {fila.error && (
            <Alert variant="destructive">
              <AlertTitle>Não foi possível carregar a fila</AlertTitle>
              <AlertDescription>{fila.error}</AlertDescription>
            </Alert>
          )}
          {fila.data && fila.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <Users />
                </EmptyMedia>
                <EmptyTitle>Nenhum contato para este vendedor</EmptyTitle>
                <EmptyDescription>
                  A fila é global: nem todo vendedor recebe contatos toda semana — quem tem carteira mais quente
                  recebe mais contatos, e isso está certo.
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {fila.data && fila.data.length > 0 && (
            <div className="overflow-x-auto">
              <Table className="table-fixed">
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[60px]">Ordem</TableHead>
                    <TableHead className="w-[220px]">Cliente</TableHead>
                    <TableHead className="w-[140px]">Vendedor</TableHead>
                    <TableHead className="w-[100px]">Chance</TableHead>
                    <TableHead className="w-[160px]">Motivo</TableHead>
                    <TableHead className="w-[160px]">Sugestão</TableHead>
                    <TableHead className="w-[260px]">Como foi a ligação</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {fila.data.map((row) => (
                    <TableRow key={`${row.vendedor}-${row.cliente_id}`}>
                      <TableCell className="whitespace-normal break-words">{row.ordem}</TableCell>
                      <TableCell className="whitespace-normal break-words">
                        <div className="font-medium">{row.razao_social}</div>
                        <div className="text-xs text-muted-foreground">
                          {row.cidade}/{row.uf} · ticket médio {formatBRL(row.ticket_medio)}
                        </div>
                      </TableCell>
                      <TableCell className="whitespace-normal break-words">{row.vendedor}</TableCell>
                      <TableCell className="whitespace-normal break-words">
                        <Badge variant={faixaVariant(row.faixa)}>
                          {formatScorePercent(row.score)} · {row.faixa}
                        </Badge>
                      </TableCell>
                      <TableCell className="whitespace-normal break-words">{row.motivo}</TableCell>
                      <TableCell className="whitespace-normal break-words text-muted-foreground">
                        {row.sugestao ?? '—'}
                      </TableCell>
                      <TableCell className="whitespace-normal break-words align-top">
                        {kpiRow && (
                          <RetornoCell
                            clienteId={Number(row.cliente_id)}
                            vendedor={row.vendedor}
                            referencia={kpiRow.referencia}
                            retornoStatus={row.retorno_status ?? null}
                            retornoComentario={row.retorno_comentario ?? null}
                            onSaved={onSaved}
                          />
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </>
  );
}

export function SemanaPage() {
  const vendedoresQuery = useAnalyticsQuery('vendedores', emptyParams);
  const [vendedor, setVendedor] = useState('Todos');
  const [reloadToken, setReloadToken] = useState(0);

  return (
    <div className="space-y-6 w-full max-w-6xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">A semana</h2>
      </div>

      <div className="flex items-center gap-3">
        <Label htmlFor="vendedor-select" className="whitespace-nowrap">
          Vendedor
        </Label>
        <Select value={vendedor} onValueChange={setVendedor}>
          <SelectTrigger id="vendedor-select" className="w-[280px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="Todos">Todos os vendedores</SelectItem>
            {vendedoresQuery.data?.map((v) => (
              <SelectItem key={v.vendedor} value={v.vendedor}>
                {v.vendedor} ({formatInt(v.contatos)})
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <DataSection key={reloadToken} vendedor={vendedor} onSaved={() => setReloadToken((t) => t + 1)} />
    </div>
  );
}
