import Link from "next/link";

const steps = [
  "Criar o projeto Supabase dedicado em sa-east-1.",
  "Vincular o repositório a um projeto Vercel dedicado.",
  "Adicionar as variáveis de ambiente sem expor valores no GitHub.",
  "Aplicar a migration inicial e executar os advisors de segurança.",
  "Ativar Google Drive e Calendly antes das redes sociais.",
  "Adicionar cada rede somente por integração oficial ou fluxo assistido.",
];

export default function SetupPage() {
  return (
    <main>
      <div className="eyebrow">Configuração</div>
      <h1>Checklist de implantação</h1>
      <p className="lead">
        A fundação já separa código público de segredos operacionais. Nenhuma
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
