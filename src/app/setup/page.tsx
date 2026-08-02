import Link from "next/link";

const steps = [
  "Criar o projeto Supabase dedicado em sa-east-1.",
  "Vincular o repositório a um projeto Vercel dedicado.",
  "Adicionar as variáveis de ambiente sem expor valores no GitHub.",
  "Aplicar as migrations e executar os advisors de segurança.",
  "Implantar o agent-orchestrator e testar somente system.healthcheck.",
  "Validar fila, retries, idempotência e aprovação humana.",
  "Ativar Google Drive e Calendly antes das redes sociais.",
  "Adicionar cada rede somente por integração oficial ou fluxo assistido.",
];

export default function SetupPage() {
  return (
    <main>
      <div className="eyebrow">Configuração</div>
      <h1>Checklist de implantação</h1>
      <p className="lead">
        A fundação separa código público de segredos operacionais. Nenhuma
        chave deve ser registrada em commits, issues, capturas ou prompts.
      </p>
      <section className="panel">
        <ol>
          {steps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
        <Link className="button" href="/">
          Voltar ao painel
        </Link>
      </section>
    </main>
  );
}
