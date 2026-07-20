# Guia de Conformidade — Apache License 2.0

Este documento descreve como manter o **WRA - Windows Resource Auditor** em
conformidade com a **Apache License, Version 2.0** ao longo do tempo. Ele
complementa os arquivos [`LICENSE`](../LICENSE) e [`NOTICE`](../NOTICE) e serve
de referência para mantenedores e colaboradores.

> Este guia é uma orientação prática de boas práticas e não constitui
> aconselhamento jurídico. Em caso de dúvida sobre um caso específico,
> consulte um advogado.

---

## 1. Arquivos de licenciamento do projeto

| Arquivo | Finalidade |
|---------|-----------|
| `LICENSE` | Texto oficial e íntegro da Apache License 2.0. Nunca deve ser resumido, traduzido ou alterado. |
| `NOTICE` | Avisos de atribuição obrigatórios (nome, copyright, licença e componentes de terceiros). |
| `Docs/LICENSING.md` | Este guia de conformidade. |
| Cabeçalho nos fontes | Aviso curto de copyright/licença no topo de cada arquivo de código (opcional, porém recomendado). |

O GitHub reconhece automaticamente a licença quando o arquivo `LICENSE`
(sem extensão) está na raiz do repositório e contém o texto padrão da
Apache 2.0 — passando a exibir "Apache-2.0" na página do projeto.

---

## 2. Como manter a conformidade

Ao **redistribuir** o WRA (com ou sem modificações, em código ou binário),
a Seção 4 da licença exige que você:

1. **Inclua uma cópia da licença** (`LICENSE`) junto da distribuição.
2. **Preserve todos os avisos** de copyright, patente, marca e atribuição
   presentes no código de origem (não remova cabeçalhos existentes).
3. **Inclua uma cópia legível do `NOTICE`**, quando ele existir, em pelo menos
   um destes locais: um arquivo `NOTICE` na distribuição, a documentação, ou
   uma tela gerada pela ferramenta onde avisos de terceiros normalmente
   apareçam.
4. **Sinalize os arquivos modificados** com um aviso destacado indicando que
   você os alterou (por exemplo, uma linha de comentário `Modified by ... on ...`
   ou uma entrada no `CHANGELOG`).

O conteúdo do `NOTICE` é **apenas informativo** e não modifica os termos da
licença. Você pode acrescentar suas próprias atribuições ao `NOTICE`, desde
que não sejam redigidas de forma que pareçam alterar a licença.

---

## 3. Quando atualizar o NOTICE

Atualize o `NOTICE` sempre que:

- **O ano ou o titular do copyright mudar** (ex.: virada de ano com novas
  contribuições relevantes, ou mudança de detentor dos direitos).
- **Um componente de terceiros for adicionado** e exigir atribuição
  (ver seção 5).
- **Um componente de terceiros for removido** — retire a atribuição
  correspondente para manter o arquivo fiel ao conteúdo distribuído.
- **A descrição oficial do projeto mudar** de forma significativa.

Mantenha o `NOTICE` **enxuto**: ele deve conter apenas avisos de atribuição
exigidos, não documentação. Detalhes de uso pertencem ao `README.md` e à
pasta `Docs/`.

---

## 4. Como tratar contribuições externas

- Pela **Seção 5** da Apache 2.0, toda contribuição enviada para inclusão no
  projeto é automaticamente licenciada sob os mesmos termos (Apache 2.0), a
  menos que o contribuidor declare explicitamente o contrário.
- **Não** é obrigatório um CLA (Contributor License Agreement) para projetos
  Apache-2.0 fora da ASF; a cláusula 5 já cobre o essencial. Adote um CLA/DCO
  apenas se desejar uma trilha formal adicional.
- Recomenda-se pedir que cada Pull Request:
  - Descreva claramente **o que foi alterado** (ajuda a cumprir a Seção 4(b)).
  - **Preserve** os cabeçalhos e avisos existentes nos arquivos tocados.
  - Adicione atribuição no `NOTICE` caso traga código de terceiros.
- Contribuidores mantêm o copyright de suas contribuições; não é necessário
  "transferir" direitos. Se desejar, mantenha um arquivo `AUTHORS` ou
  `CONTRIBUTORS` para créditos — isso é opcional e não substitui o `NOTICE`.

---

## 5. Como adicionar bibliotecas de terceiros

Antes de incorporar qualquer componente de terceiros, verifique a
**compatibilidade de licença** com a Apache 2.0:

1. **Confirme a licença** do componente. São geralmente compatíveis para
   inclusão: Apache-2.0, MIT, BSD (2/3 cláusulas), ISC, entre outras
   permissivas. Licenças fortemente copyleft (por exemplo, GPL) **não** são
   compatíveis com a redistribuição sob Apache-2.0 — evite-as.
2. **Preserve o texto de licença** do terceiro. O caminho usual é manter os
   textos em uma pasta dedicada, por exemplo `licenses/<componente>/LICENSE`.
3. **Adicione a atribuição ao `NOTICE`**, listando nome do componente,
   copyright e licença, na seção "Third-party components".
4. **Sinalize modificações**: se você alterar arquivos do terceiro, marque-os
   conforme a Seção 4(b).
5. **Registre a inclusão** no `CHANGELOG.md`.

Exemplo de entrada no `NOTICE`:

```
This product includes software developed by <Autor/Projeto>
(<URL do projeto>), licensed under the <Nome da Licença>.
```

> Observação sobre o WRA: por decisão de projeto, a ferramenta é offline e usa
> apenas recursos nativos do Windows/PowerShell/.NET, sem dependências de
> terceiros empacotadas. Enquanto isso for verdade, a seção de terceiros do
> `NOTICE` permanece vazia (apenas com o aviso informativo).

---

## 6. Como preservar os avisos obrigatórios de copyright

- **Não remova** cabeçalhos de licença/copyright existentes ao editar arquivos.
- Ao **criar novos arquivos de código**, aplique o cabeçalho padrão do projeto
  (ver `Docs/LICENSE-HEADER-POWERSHELL.txt`), preenchido com o ano corrente.
- **Não** é necessário repetir o texto integral da licença em cada arquivo —
  o cabeçalho curto que aponta para a Apache 2.0 é suficiente e é exatamente o
  formato recomendado no apêndice "How to apply the Apache License" da própria
  licença.
- Mantenha o **`LICENSE` na raiz** para o reconhecimento automático do GitHub.
- Ao gerar distribuições (por exemplo, o `.zip` de release), **inclua**
  `LICENSE` e `NOTICE` no pacote.

---

## 7. Checklist rápido de release

- [ ] `LICENSE` presente na raiz, íntegro (Apache-2.0 oficial).
- [ ] `NOTICE` presente e atualizado (ano, titular, terceiros).
- [ ] Ano do copyright correto em `LICENSE`/`NOTICE`.
- [ ] Novos arquivos de código com cabeçalho padrão.
- [ ] Arquivos modificados de terceiros sinalizados (se houver).
- [ ] `README.md` com a seção **License** apontando para `LICENSE`.
- [ ] `LICENSE` e `NOTICE` incluídos no pacote distribuído.
- [ ] GitHub exibindo "Apache-2.0" na página do repositório.

---

**WRA - Windows Resource Auditor** — Desenvolvido por Edsilas.
Distribuído sob a Apache License, Version 2.0.
