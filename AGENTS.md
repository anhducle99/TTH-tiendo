# AGENTS.md

## Mục tiêu dự án

Xây dựng ứng dụng **Tiến độ dự án PTPK** theo hướng đơn giản, dễ sử dụng và dễ bảo trì. Dự án đang ở giai đoạn làm rõ yêu cầu; không tự giả định ý nghĩa nghiệp vụ của PTPK hoặc chọn kiến trúc lớn khi chưa có đủ dữ liệu.

## Cách làm việc

- Trao đổi với người dùng chủ yếu bằng tiếng Việt; giữ nguyên thuật ngữ kỹ thuật tiếng Anh khi rõ nghĩa hơn.
- Trước khi thay đổi, đọc `README.md`, `docs/PROJECT-BRIEF.md`, `docs/DECISIONS.md` và kiểm tra trạng thái repository.
- Phân biệt rõ Business Problem, User Need, Business Rule và Technical Solution.
- Chỉ hỏi lại khi thiếu quyết định có thể làm thay đổi đáng kể phạm vi, dữ liệu hoặc kiến trúc.
- Với quyết định nhỏ, chọn phương án đơn giản, phổ biến và có thể đảo ngược; nêu rõ giả định.
- Không thêm dependency, service trả phí hoặc hạ tầng mới nếu chưa chứng minh được sự cần thiết.
- Không ghi secret, token, mật khẩu hoặc dữ liệu nhạy cảm vào source code và tài liệu Git.
- Không xóa dữ liệu, thay đổi cấu hình máy hoặc publish ra ngoài khi chưa được yêu cầu rõ ràng.

## Khi phân tích nghiệp vụ

- Làm rõ stakeholder, current state, desired state, phạm vi, business rule, ngoại lệ và edge case.
- Khi phù hợp, chuyển yêu cầu thành User Story và Acceptance Criteria kiểm thử được.
- Cập nhật kết quả đã chốt vào `docs/PROJECT-BRIEF.md`; ghi quyết định quan trọng vào `docs/DECISIONS.md`.

## Khi viết code

- Tuân theo cấu trúc và convention đã có; ưu tiên thay đổi nhỏ, dễ review.
- Không thay đổi hành vi hiện có ngoài phạm vi yêu cầu.
- Xử lý trạng thái loading, empty, error và quyền truy cập khi có liên quan.
- Có validation ở ranh giới nhập liệu và thông báo lỗi dễ hiểu.
- Sau khi chỉnh sửa, chạy formatter, lint, type-check, test và build tương ứng với stack đang dùng.
- Nếu ứng dụng có giao diện, chạy ứng dụng và kiểm tra luồng chính trên trình duyệt trước khi kết luận hoàn thành.

## Definition of Done

Một hạng mục chỉ hoàn thành khi:

1. Đáp ứng Acceptance Criteria đã thống nhất.
2. Không làm hỏng hành vi liên quan.
3. Các kiểm tra tự động liên quan đều đạt.
4. Luồng giao diện chính đã được xác minh nếu có UI.
5. Tài liệu hoặc quyết định liên quan đã được cập nhật.
6. Tóm tắt rõ file đã đổi, cách kiểm tra và rủi ro còn lại.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **tien-do-phong-kham** (1158 symbols, 2537 relationships, 69 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/tien-do-phong-kham/context` | Codebase overview, check index freshness |
| `gitnexus://repo/tien-do-phong-kham/clusters` | All functional areas |
| `gitnexus://repo/tien-do-phong-kham/processes` | All execution flows |
| `gitnexus://repo/tien-do-phong-kham/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
