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
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@databricks/appkit-ui/react';
import { ClipboardList } from 'lucide-react';
import { formatInt } from '../../utils/formatters';

const emptyParams = {};

export function AcompanhamentoPage() {
  const acompanhamento = useAnalyticsQuery('acompanhamento', emptyParams);

  const rows = acompanhamento.data ?? [];
  const totalFila = rows.reduce((acc, r) => acc + Number(r.na_fila), 0);
  const totalTrabalhados = rows.reduce((acc, r) => acc + Number(r.trabalhados), 0);
  const totalVendeu = rows.reduce((acc, r) => acc + Number(r.vendeu), 0);

  return (
    <div className="space-y-6 w-full max-w-6xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Acompanhamento</h2>
        <p className="text-sm text-muted-foreground mt-1">O que a equipe já registrou sobre a fila da semana.</p>
      </div>

      {acompanhamento.loading && (
        <div className="space-y-2">
          <Skeleton className="h-8 w-2/3" />
          <Skeleton className="h-64 w-full" />
        </div>
      )}

      {acompanhamento.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível carregar o acompanhamento</AlertTitle>
          <AlertDescription>{acompanhamento.error}</AlertDescription>
        </Alert>
      )}

      {acompanhamento.data && totalTrabalhados === 0 && (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <ClipboardList />
            </EmptyMedia>
            <EmptyTitle>Ainda ninguém registrou um retorno</EmptyTitle>
            <EmptyDescription>
              Esse número aparece assim que o time começar a marcar o desfecho das ligações na aba &ldquo;A
              semana&rdquo;. É esse registro que vira dado de treino do modelo na próxima semana.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {acompanhamento.data && totalTrabalhados > 0 && (
        <>
          <p className="text-lg">
            <strong>{formatInt(totalTrabalhados)}</strong> de <strong>{formatInt(totalFila)}</strong> contatos da
            fila já foram trabalhados, e <strong>{formatInt(totalVendeu)}</strong> viraram pedido.
          </p>

          <Card>
            <CardHeader>
              <CardTitle>Trabalhados vs. vendeu, por vendedor</CardTitle>
              <CardDescription>Barra cheia = já trabalhado. Trecho colorido = virou pedido.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {rows.map((r) => {
                const naFila = Number(r.na_fila) || 1;
                const pctTrabalhados = (Number(r.trabalhados) / naFila) * 100;
                const pctVendeu = (Number(r.vendeu) / naFila) * 100;
                return (
                  <div key={r.vendedor} className="grid grid-cols-[120px_1fr_auto] items-center gap-3 text-sm">
                    <span className="truncate">{r.vendedor}</span>
                    <div className="relative h-4 rounded bg-muted overflow-hidden">
                      <div className="absolute inset-y-0 left-0 bg-secondary" style={{ width: `${pctTrabalhados}%` }} />
                      <div className="absolute inset-y-0 left-0 bg-primary" style={{ width: `${pctVendeu}%` }} />
                    </div>
                    <span className="text-xs text-muted-foreground whitespace-nowrap">
                      {formatInt(r.trabalhados)}/{formatInt(r.na_fila)} · {formatInt(r.vendeu)} vendas
                    </span>
                  </div>
                );
              })}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Detalhe por vendedor</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Vendedor</TableHead>
                      <TableHead>Na fila</TableHead>
                      <TableHead>Trabalhados</TableHead>
                      <TableHead>Vendeu</TableHead>
                      <TableHead>Vai pensar</TableHead>
                      <TableHead>Sem interesse</TableHead>
                      <TableHead>Não atendeu</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((r) => (
                      <TableRow key={r.vendedor}>
                        <TableCell>{r.vendedor}</TableCell>
                        <TableCell>{formatInt(r.na_fila)}</TableCell>
                        <TableCell>{formatInt(r.trabalhados)}</TableCell>
                        <TableCell>{formatInt(r.vendeu)}</TableCell>
                        <TableCell>{formatInt(r.vai_pensar)}</TableCell>
                        <TableCell>{formatInt(r.sem_interesse)}</TableCell>
                        <TableCell>{formatInt(r.nao_atendeu)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
