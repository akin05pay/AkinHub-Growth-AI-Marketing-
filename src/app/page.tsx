import Link from "next/link";
import { hasSupabaseConfig } from "@/lib/env";
import { modules } from "@/lib/modules";

export default function Home() {
  const configured = hasSupabaseConfig();

  return (
    <main>
      <header>
        <div>
          <div className="eyebrow">AkinHub · Growth Operating System</div>
          <h1>Conteúdo, relacionamento e vendas com controle humano.</h1>
          <p className="lead">
            Fundação técnica do Scout, Hunter, Content, SDR e Closer. O sistema
            nasce multilíngue, auditável e preparado para Google Drive,
            Calendly e integrações oficiais das redes sociais.
          </p>
        </div>
        <span className="badge">Bootstrap v0.1</span>
      </header>

      <section className="grid" aria-label="Módulos do produto">
        {modules.map((module) => (
          <article className="card" key={module.name}>
            <strong>{module.stage}</strong>
            <h2>{module.name}</h2>
            <p>{module.purpose}</p>
          </article>
        ))}

        <article className="panel">
          <h2>Estado da infraestrutura</h2>
          <p>
            Supabase: {configured ? "variáveis detectadas" : "aguardando projeto dedicado"}.
          </p>
          {!configured && (
            <p className="warning">
              O build funciona sem credenciais. Autenticação e dados só serão
              ativados depois que as variáveis protegidas forem configuradas.
            </p>
          )}
          <Link className="button" href="/setup">
            Ver checklist técnico
          </Link>
        </article>

        <article className="panel">
          <h2>Princípio operacional</h2>
          <p>
            Descoberta, classificação e geração podem ser automatizadas. Ações
            de publicação, comentários e mensagens começam com aprovação e
            limites por canal, preservando reputação e conformidade.
          </p>
        </article>
      </section>
    </main>
  );
}
