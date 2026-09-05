import { useEffect, useState } from 'react';
import { GenieChat, Alert, AlertTitle, AlertDescription } from '@databricks/appkit-ui/react';
import { Info } from 'lucide-react';

export function PerguntarPage() {
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/quem-sou')
      .then((r) => r.json() as Promise<{ email: string }>)
      .then((d) => setEmail(d.email))
      .catch(() => setEmail(null));
  }, []);

  return (
    <div className="space-y-4 w-full max-w-4xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
        <p className="text-sm text-muted-foreground mt-1">
          {email ? <>Logado como {email}.</> : null} Pergunte com as palavras do dia a dia — fila, retorno,
          desempenho do modelo.
        </p>
      </div>

      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>A resposta é gerada por IA</AlertTitle>
        <AlertDescription>
          Confira sempre o SQL gerado (botão “Show generated code” em cada resposta) antes de levar um número para
          a reunião.
        </AlertDescription>
      </Alert>

      <div style={{ height: 600 }} className="border rounded-lg overflow-hidden">
        <GenieChat alias="default" />
      </div>
    </div>
  );
}
