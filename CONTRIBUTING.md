# 贡献指南 (CONTRIBUTING.md)

感谢你对 `ngx-cert-manager` 项目的关注与贡献！

## 🛠️ 工具与环境规范

为保持项目一致性与开发体验，本项目严格遵循以下环境工具规范：
- **Python 工具**：统一使用 [`uv`](https://github.com/astral-sh/uv)
- **Node.js 工具**：统一使用 [`pnpm`](https://pnpm.io/)
- **Pull Request 提交与管理**：统一使用 GitHub CLI [`gh`](https://cli.github.com/)

---

## 📋 提交与测试流程

1. **创建分支**：
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **本地测试与语法自检**：
   在提交代码前，确保所有测试用例与静态分析检查全部通过：
   ```bash
   make lint
   make test
   ```

3. **提交 PR**：
   使用 GitHub CLI 提交 Pull Request：
   ```bash
   gh pr create --title "feat: describe your change" --body "Detailed description of the PR"
   ```

---

## 📐 Shell 编码规范

1. 保持模块化设计，新功能封装于 `lib/` 对应子模块中。
2. 模块内局部变量一律使用 `local` 修饰，避免全局变量污染。
3. 所有变量与参数引用必须使用双引号包裹，防止路径空格分词错误。
4. 任何 Nginx 写入操作必须支持 `.tmp` 预校验与 `.backup/` 原子回滚。
