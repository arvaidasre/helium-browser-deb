# Site Directory

This directory contains the GitHub Pages content for the Helium Browser repository.

## Files

- **index.html.template** — Main landing page template (processed by CI)
- **install.sh** — One-line installer for Debian/Ubuntu
- **install-rpm.sh** — One-line installer for Fedora/RHEL
- **public/** — Generated repository content (APT/RPM repos, created by CI)

## Features

- ✅ Modern, clean design
- ✅ Tabbed interface (Debian/Ubuntu vs Fedora/RHEL)
- ✅ GPG signing information
- ✅ One-click copy for commands
- ✅ Responsive layout
- ✅ Accordion for manual setup instructions

## Local Development

To preview the site locally:

```bash
cd site
python3 -m http.server 8000
# Open http://localhost:8000/index.html.template
```

Note: The template uses absolute URLs that point to the live GitHub Pages site.
For local testing, you may need to adjust the URLs.
