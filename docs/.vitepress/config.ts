export default {
  lang: "en-US",
  title: "quickbox",
  description: "Minimal macOS quick capture app",
  base: "/quickbox/",
  lastUpdated: true,
  themeConfig: {
    nav: [
      { text: "Guide", link: "/getting-started" },
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
          { text: "FAQ", link: "/faq" },
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
