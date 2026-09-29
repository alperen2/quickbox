// usepigeon.cc serves the site at the root; GitHub Pages keeps /quickbox/ so existing links work.
const base = process.env.DOCS_BASE ?? "/quickbox/";

export default {
  lang: "en-US",
  title: "Pigeon",
  description: "Agentic to-do tracker: quick capture for you and your AI agents",
  base,
  cleanUrls: base === "/",
  head: [["link", { rel: "icon", type: "image/svg+xml", href: `${base}pigeon-mark.svg` }]],
  lastUpdated: true,
  themeConfig: {
    logo: "/pigeon-mark.svg",
    nav: [
      { text: "Guide", link: "/getting-started" },
      { text: "Agents", link: "/agents" },
      { text: "Support", link: "/support" },
      { text: "Privacy", link: "/privacy" },
      { text: "Contributing", link: "/contributing" },
      { text: "GitHub", link: "https://github.com/alperen2/quickbox" }
    ],
    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "Getting Started", link: "/getting-started" },
          { text: "Usage", link: "/usage" },
          { text: "Settings", link: "/settings" },
          { text: "Connect an AI agent", link: "/agents" },
          { text: "FAQ", link: "/faq" },
          { text: "Support", link: "/support" },
          { text: "Privacy", link: "/privacy" },
          { text: "Contributing", link: "/contributing" }
        ]
      },
      {
        text: "Operations",
        items: [
          { text: "Release Playbook", link: "/release-playbook" },
          { text: "Release Process", link: "/release-process" },
          { text: "Support Runbook", link: "/support-runbook" }
        ]
      }
    ],
    socialLinks: [{ icon: "github", link: "https://github.com/alperen2/quickbox" }],
    editLink: {
      pattern: "https://github.com/alperen2/quickbox/edit/main/docs/:path",
      text: "Edit this page on GitHub"
    },
    search: {
      provider: "local"
    },
    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2026 alperen2"
    }
  }
} satisfies import("vitepress").UserConfig;
