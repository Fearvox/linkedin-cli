# LinkedIn CLI Adapters — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build opencli adapters that give LinkedIn full read+write capability from the terminal — post, like, comment, repost, DM, profile view — all via `opencli linkedin <command>`.

**Architecture:** Each adapter is a standalone YAML pipeline that runs JS in the user's authenticated Chrome session via opencli's Browser Bridge. All write operations use LinkedIn's internal Voyager REST API with JSESSIONID CSRF tokens (same pattern as the existing `search` adapter). No OAuth app needed — piggybacks on the user's logged-in browser.

**Tech Stack:** opencli v1.6.8 YAML adapter format, LinkedIn Voyager API, Browser Bridge extension

**Tier Classification:** Tier 2 (browser needed, no desktop) — all operations run through headless browser with existing Chrome session cookies.

**Dry-Run Gate:** Every write adapter (post, like, comment, repost, send-dm) MUST support `--dry-run` flag that shows the projected mutation without executing it.

---

## File Structure

All adapters go into the opencli custom adapters directory so they're picked up automatically:

```
~/.opencli/clis/linkedin/
├── post.yaml          — Create text post (with optional image URL)
├── like.yaml          — Like/unlike a post by URL or URN
├── comment.yaml       — Comment on a post
├── repost.yaml        — Repost/share with optional commentary
├── send-dm.yaml       — Send DM to a connection
├── profile.yaml       — View a person's public profile
├── connections.yaml   — List your connections
└── notifications.yaml — Read recent notifications
```

Source + tests live in this workspace for version control:

```
~/.openclaw/workspace/linkedin-cli/
├── PLAN.md            — This file
├── README.md          — Usage docs
├── adapters/          — YAML sources (symlinked to ~/.opencli/clis/linkedin/)
│   ├── post.yaml
│   ├── like.yaml
│   ├── comment.yaml
│   ├── repost.yaml
│   ├─�� send-dm.yaml
│   ├── profile.yaml
│   ├── connections.yaml
│   └─��� notifications.yaml
├── tests/             — Smoke tests
│   └── test-all.sh
└── install.sh         — Symlink adapters into opencli
```

---

## Shared: Voyager API Auth Pattern

Every adapter that calls LinkedIn's internal API needs this JS snippet to get CSRF:

```javascript
const jsession = document.cookie.split(';').map(p => p.trim())
  .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
if (!jsession) throw new Error('LinkedIn JSESSIONID not found. Sign in first.');
const csrf = jsession.replace(/^"|"$/g, '');
```

Then fetch with:
```javascript
fetch(apiPath, {
  method: 'POST', // or GET
  credentials: 'include',
  headers: {
    'csrf-token': csrf,
    'x-restli-protocol-version': '2.0.0',
    'Content-Type': 'application/json',
  },
  body: JSON.stringify(payload),
});
```

---

## Task 1: Install Script + Project Scaffold

**Files:**
- Create: `~/.openclaw/workspace/linkedin-cli/install.sh`
- Create: `~/.openclaw/workspace/linkedin-cli/adapters/` (directory)

- [ ] **Step 1: Create install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ADAPTER_DIR="$HOME/.opencli/clis/linkedin"
SOURCE_DIR="$(cd "$(dirname "$0")/adapters" && pwd)"

mkdir -p "$ADAPTER_DIR"

for yaml in "$SOURCE_DIR"/*.yaml; do
  name=$(basename "$yaml")
  # Skip if opencli already ships this adapter (search, timeline are built-in)
  if [[ "$name" == "search.yaml" || "$name" == "timeline.yaml" ]]; then
    echo "SKIP $name (built-in)"
    continue
  fi
  ln -sf "$yaml" "$ADAPTER_DIR/$name"
  echo "LINK $name → $ADAPTER_DIR/$name"
done

echo "Done. Run 'opencli linkedin --help' to see all commands."
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x install.sh
./install.sh
# Expected: "Done. Run 'opencli linkedin --help' to see all commands."
```

- [ ] **Step 3: Commit**

```bash
git init
git add install.sh PLAN.md
git commit -m "init: project scaffold + install script"
```

---

## Task 2: `linkedin profile` (Read — warm-up)

**Files:**
- Create: `adapters/profile.yaml`

Start with a read-only adapter to validate the YAML pipeline pattern works.

- [ ] **Step 1: Write profile.yaml**

```yaml
site: linkedin
name: profile
description: View a LinkedIn member's public profile
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  url:
    positional: true
    type: string
    required: true
    description: "LinkedIn profile URL (e.g. https://www.linkedin.com/in/username)"

columns: [name, headline, location, connections, about, experience, education, profile_url]

pipeline:
  - navigate: ${{ args.url }}
  - wait: 3
  - evaluate: |
      (() => {
        const normalize = v => String(v || '').replace(/\s+/g, ' ').trim();
        const textOf = (sel) => { const el = document.querySelector(sel); return el ? normalize(el.textContent) : ''; };

        const name = textOf('h1.text-heading-xlarge') || textOf('h1');
        const headline = textOf('.text-body-medium.break-words');
        const location = textOf('.text-body-small.inline.t-black--light.break-words');
        const connectionsEl = document.querySelector('li.text-body-small span.t-bold');
        const connections = connectionsEl ? normalize(connectionsEl.textContent) : '';

        // About section
        const aboutSection = document.querySelector('#about ~ .display-flex .inline-show-more-text');
        const about = aboutSection ? normalize(aboutSection.textContent) : '';

        // Experience — first 3 positions
        const expItems = Array.from(document.querySelectorAll('#experience ~ .pvs-list__outer-container li.pvs-list__paged-list-item')).slice(0, 3);
        const experience = expItems.map(li => normalize(li.textContent).slice(0, 120)).join(' | ');

        // Education — first 2
        const eduItems = Array.from(document.querySelectorAll('#education ~ .pvs-list__outer-container li.pvs-list__paged-list-item')).slice(0, 2);
        const education = eduItems.map(li => normalize(li.textContent).slice(0, 100)).join(' | ');

        return [{
          name, headline, location, connections, about: about.slice(0, 300),
          experience, education, profile_url: window.location.href
        }];
      })()
  - map:
      name: ${{ item.name }}
      headline: ${{ item.headline }}
      location: ${{ item.location }}
      connections: ${{ item.connections }}
      about: ${{ item.about }}
      experience: ${{ item.experience }}
      education: ${{ item.education }}
      profile_url: ${{ item.profile_url }}
```

- [ ] **Step 2: Install and test**

```bash
./install.sh
opencli linkedin profile "https://www.linkedin.com/in/williamhgates" --format json
# Expected: JSON with name, headline, location fields populated
```

- [ ] **Step 3: Commit**

```bash
git add adapters/profile.yaml
git commit -m "feat: add linkedin profile adapter"
```

---

## Task 3: `linkedin post` (Write — core)

**Files:**
- Create: `adapters/post.yaml`

- [ ] **Step 1: Write post.yaml**

```yaml
site: linkedin
name: post
description: Create a LinkedIn text post
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  text:
    positional: true
    type: string
    required: true
    description: "Post text content"
  visibility:
    type: string
    default: "PUBLIC"
    description: "PUBLIC or CONNECTIONS"
  dry-run:
    type: bool
    default: false
    description: "Preview without posting"

columns: [status, post_url, visibility, text_preview]

pipeline:
  - navigate: "https://www.linkedin.com/feed/"
  - wait: 3
  - evaluate: |
      (async () => {
        const text = ${{ args.text | json }};
        const visibility = ${{ args.visibility | json }};
        const dryRun = ${{ args['dry-run'] | json }};

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found. Sign in first.');
        const csrf = jsession.replace(/^"|"$/g, '');

        if (dryRun) {
          return [{
            status: 'DRY_RUN',
            post_url: '',
            visibility: visibility,
            text_preview: text.slice(0, 200)
          }];
        }

        const payload = {
          author: 'urn:li:person:' + (await fetch('/voyager/api/me', {
            credentials: 'include',
            headers: { 'csrf-token': csrf }
          }).then(r => r.json()).then(d => d.miniProfile?.entityUrn?.split(':').pop() || d.plainId)),
          lifecycleState: 'PUBLISHED',
          specificContent: {
            'com.linkedin.ugc.ShareContent': {
              shareCommentary: { text: text },
              shareMediaCategory: 'NONE'
            }
          },
          visibility: {
            'com.linkedin.ugc.MemberNetworkVisibility': visibility
          }
        };

        const res = await fetch('/voyager/api/contentcreation/normalizedShares', {
          method: 'POST',
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
        });

        if (!res.ok) {
          const err = await res.text();
          throw new Error('Post failed: HTTP ' + res.status + ' — ' + err.slice(0, 200));
        }

        const result = await res.json();
        const shareUrn = result?.urn || result?.value?.urn || '';
        const shareId = shareUrn.split(':').pop() || '';
        const postUrl = shareId ? 'https://www.linkedin.com/feed/update/urn:li:share:' + shareId + '/' : '';

        return [{
          status: 'POSTED',
          post_url: postUrl,
          visibility: visibility,
          text_preview: text.slice(0, 200)
        }];
      })()
  - map:
      status: ${{ item.status }}
      post_url: ${{ item.post_url }}
      visibility: ${{ item.visibility }}
      text_preview: ${{ item.text_preview }}
```

- [ ] **Step 2: Install and dry-run test**

```bash
./install.sh
opencli linkedin post "Test post from CLI" --dry-run --format json
# Expected: { status: "DRY_RUN", visibility: "PUBLIC", text_preview: "Test post from CLI" }
```

- [ ] **Step 3: Live test (user confirmation required)**

```bash
opencli linkedin post "Test post — will delete immediately" --format json
# Expected: { status: "POSTED", post_url: "https://linkedin.com/feed/update/..." }
# Then manually delete the test post
```

- [ ] **Step 4: Commit**

```bash
git add adapters/post.yaml
git commit -m "feat: add linkedin post adapter with dry-run support"
```

---

## Task 4: `linkedin like`

**Files:**
- Create: `adapters/like.yaml`

- [ ] **Step 1: Write like.yaml**

```yaml
site: linkedin
name: like
description: Like a LinkedIn post by URL
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  url:
    positional: true
    type: string
    required: true
    description: "LinkedIn post URL (e.g. https://www.linkedin.com/feed/update/urn:li:activity:123/)"
  dry-run:
    type: bool
    default: false
    description: "Preview without liking"

columns: [status, post_url, action]

pipeline:
  - navigate: ${{ args.url }}
  - wait: 3
  - evaluate: |
      (async () => {
        const postUrl = ${{ args.url | json }};
        const dryRun = ${{ args['dry-run'] | json }};

        // Extract activity URN from URL or page
        let activityUrn = '';
        const urnMatch = postUrl.match(/urn:li:activity:(\d+)/);
        if (urnMatch) {
          activityUrn = 'urn:li:activity:' + urnMatch[1];
        } else {
          // Try to find it in the page
          const allElements = document.querySelectorAll('[data-urn*="activity"]');
          for (const el of allElements) {
            const match = el.getAttribute('data-urn')?.match(/urn:li:activity:\d+/);
            if (match) { activityUrn = match[0]; break; }
          }
        }
        if (!activityUrn) {
          // Fallback: scan all attributes
          const allEls = document.querySelectorAll('*');
          for (const el of allEls) {
            for (const attr of el.attributes) {
              const m = attr.value.match(/urn:li:activity:(\d+)/);
              if (m) { activityUrn = 'urn:li:activity:' + m[1]; break; }
            }
            if (activityUrn) break;
          }
        }
        if (!activityUrn) throw new Error('Could not find activity URN on this page.');

        if (dryRun) {
          return [{ status: 'DRY_RUN', post_url: postUrl, action: 'LIKE ' + activityUrn }];
        }

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found. Sign in first.');
        const csrf = jsession.replace(/^"|"$/g, '');

        const res = await fetch('/voyager/api/voyagerSocialDashReactions?threadUrn=' + encodeURIComponent(activityUrn), {
          method: 'POST',
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ reactionType: 'LIKE' }),
        });

        if (!res.ok) {
          const err = await res.text();
          throw new Error('Like failed: HTTP ' + res.status + ' — ' + err.slice(0, 200));
        }

        return [{ status: 'LIKED', post_url: postUrl, action: 'LIKE ' + activityUrn }];
      })()
  - map:
      status: ${{ item.status }}
      post_url: ${{ item.post_url }}
      action: ${{ item.action }}
```

- [ ] **Step 2: Install and dry-run test**

```bash
./install.sh
opencli linkedin like "https://www.linkedin.com/feed/update/urn:li:activity:7314825673041756161/" --dry-run --format json
# Expected: { status: "DRY_RUN", action: "LIKE urn:li:activity:..." }
```

- [ ] **Step 3: Commit**

```bash
git add adapters/like.yaml
git commit -m "feat: add linkedin like adapter with dry-run"
```

---

## Task 5: `linkedin comment`

**Files:**
- Create: `adapters/comment.yaml`

- [ ] **Step 1: Write comment.yaml**

```yaml
site: linkedin
name: comment
description: Comment on a LinkedIn post
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  url:
    positional: true
    type: string
    required: true
    description: "LinkedIn post URL"
  text:
    type: string
    required: true
    description: "Comment text"
  dry-run:
    type: bool
    default: false
    description: "Preview without commenting"

columns: [status, post_url, comment_preview]

pipeline:
  - navigate: ${{ args.url }}
  - wait: 3
  - evaluate: |
      (async () => {
        const postUrl = ${{ args.url | json }};
        const commentText = ${{ args.text | json }};
        const dryRun = ${{ args['dry-run'] | json }};

        // Extract activity URN
        let activityUrn = '';
        const urnMatch = postUrl.match(/urn:li:activity:(\d+)/);
        if (urnMatch) {
          activityUrn = 'urn:li:activity:' + urnMatch[1];
        } else {
          const allEls = document.querySelectorAll('*');
          for (const el of allEls) {
            for (const attr of el.attributes) {
              const m = attr.value.match(/urn:li:activity:(\d+)/);
              if (m) { activityUrn = 'urn:li:activity:' + m[1]; break; }
            }
            if (activityUrn) break;
          }
        }
        if (!activityUrn) throw new Error('Could not find activity URN.');

        if (dryRun) {
          return [{ status: 'DRY_RUN', post_url: postUrl, comment_preview: commentText.slice(0, 200) }];
        }

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found.');
        const csrf = jsession.replace(/^"|"$/g, '');

        const res = await fetch('/voyager/api/voyagerSocialDashComments', {
          method: 'POST',
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            threadUrn: activityUrn,
            comment: { values: [{ value: commentText }] },
          }),
        });

        if (!res.ok) {
          const err = await res.text();
          throw new Error('Comment failed: HTTP ' + res.status + ' — ' + err.slice(0, 200));
        }

        return [{ status: 'COMMENTED', post_url: postUrl, comment_preview: commentText.slice(0, 200) }];
      })()
  - map:
      status: ${{ item.status }}
      post_url: ${{ item.post_url }}
      comment_preview: ${{ item.comment_preview }}
```

- [ ] **Step 2: Install, dry-run, commit**

```bash
./install.sh
opencli linkedin comment "https://www.linkedin.com/feed/update/urn:li:activity:123/" --text "Great post!" --dry-run --format json
git add adapters/comment.yaml
git commit -m "feat: add linkedin comment adapter with dry-run"
```

---

## Task 6: `linkedin repost`

**Files:**
- Create: `adapters/repost.yaml`

- [ ] **Step 1: Write repost.yaml**

```yaml
site: linkedin
name: repost
description: Repost/share a LinkedIn post with optional commentary
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  url:
    positional: true
    type: string
    required: true
    description: "Original post URL to repost"
  text:
    type: string
    default: ""
    description: "Optional commentary text"
  dry-run:
    type: bool
    default: false
    description: "Preview without reposting"

columns: [status, original_url, repost_url, has_commentary]

pipeline:
  - navigate: ${{ args.url }}
  - wait: 3
  - evaluate: |
      (async () => {
        const originalUrl = ${{ args.url | json }};
        const commentary = ${{ args.text | json }};
        const dryRun = ${{ args['dry-run'] | json }};

        // Extract share/activity URN
        let shareUrn = '';
        const activityMatch = originalUrl.match(/urn:li:activity:(\d+)/);
        if (activityMatch) {
          shareUrn = 'urn:li:activity:' + activityMatch[1];
        } else {
          const allEls = document.querySelectorAll('*');
          for (const el of allEls) {
            for (const attr of el.attributes) {
              const m = attr.value.match(/urn:li:(?:activity|share):(\d+)/);
              if (m) { shareUrn = m[0]; break; }
            }
            if (shareUrn) break;
          }
        }
        if (!shareUrn) throw new Error('Could not find share/activity URN.');

        if (dryRun) {
          return [{
            status: 'DRY_RUN', original_url: originalUrl,
            repost_url: '', has_commentary: commentary ? 'yes' : 'no'
          }];
        }

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found.');
        const csrf = jsession.replace(/^"|"$/g, '');

        // Get own member URN
        const me = await fetch('/voyager/api/me', {
          credentials: 'include',
          headers: { 'csrf-token': csrf }
        }).then(r => r.json());
        const personId = me.miniProfile?.entityUrn?.split(':').pop() || me.plainId;

        const payload = {
          author: 'urn:li:person:' + personId,
          lifecycleState: 'PUBLISHED',
          specificContent: {
            'com.linkedin.ugc.ShareContent': {
              shareCommentary: { text: commentary },
              shareMediaCategory: 'NONE'
            }
          },
          visibility: { 'com.linkedin.ugc.MemberNetworkVisibility': 'PUBLIC' },
          originalShare: shareUrn,
        };

        const res = await fetch('/voyager/api/contentcreation/normalizedShares', {
          method: 'POST',
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
        });

        if (!res.ok) {
          const err = await res.text();
          throw new Error('Repost failed: HTTP ' + res.status + ' — ' + err.slice(0, 200));
        }

        const result = await res.json();
        const newUrn = result?.urn || result?.value?.urn || '';
        const newId = newUrn.split(':').pop() || '';
        const repostUrl = newId ? 'https://www.linkedin.com/feed/update/urn:li:share:' + newId + '/' : '';

        return [{
          status: 'REPOSTED', original_url: originalUrl,
          repost_url: repostUrl, has_commentary: commentary ? 'yes' : 'no'
        }];
      })()
  - map:
      status: ${{ item.status }}
      original_url: ${{ item.original_url }}
      repost_url: ${{ item.repost_url }}
      has_commentary: ${{ item.has_commentary }}
```

- [ ] **Step 2: Install, dry-run, commit**

```bash
./install.sh
opencli linkedin repost "https://www.linkedin.com/feed/update/urn:li:activity:123/" --text "Check this out" --dry-run --format json
git add adapters/repost.yaml
git commit -m "feat: add linkedin repost adapter with dry-run"
```

---

## Task 7: `linkedin send-dm`

**Files:**
- Create: `adapters/send-dm.yaml`

- [ ] **Step 1: Write send-dm.yaml**

```yaml
site: linkedin
name: send-dm
description: Send a direct message to a LinkedIn connection
domain: www.linkedin.com
strategy: cookie
browser: true

args:
  profile:
    positional: true
    type: string
    required: true
    description: "Recipient profile URL or vanity name"
  text:
    type: string
    required: true
    description: "Message text"
  dry-run:
    type: bool
    default: false
    description: "Preview without sending"

columns: [status, recipient, message_preview]

pipeline:
  - navigate: "https://www.linkedin.com/feed/"
  - wait: 2
  - evaluate: |
      (async () => {
        const profileInput = ${{ args.profile | json }};
        const messageText = ${{ args.text | json }};
        const dryRun = ${{ args['dry-run'] | json }};

        const jsession = document.cookie.split(';').map(p => p.trim())
          .find(p => p.startsWith('JSESSIONID='))?.slice('JSESSIONID='.length);
        if (!jsession) throw new Error('LinkedIn JSESSIONID not found.');
        const csrf = jsession.replace(/^"|"$/g, '');

        // Resolve profile URL to member URN
        let profileUrl = profileInput;
        if (!profileUrl.startsWith('http')) {
          profileUrl = 'https://www.linkedin.com/in/' + profileUrl.replace(/^\/in\//, '');
        }
        const vanity = profileUrl.match(/\/in\/([^/?]+)/)?.[1];
        if (!vanity) throw new Error('Cannot parse profile URL: ' + profileInput);

        // Get member profile to find their entityUrn
        const profileRes = await fetch('/voyager/api/identity/profiles/' + vanity, {
          credentials: 'include',
          headers: { 'csrf-token': csrf, 'x-restli-protocol-version': '2.0.0' }
        });
        if (!profileRes.ok) throw new Error('Profile lookup failed: HTTP ' + profileRes.status);
        const profileData = await profileRes.json();
        const recipientUrn = profileData.entityUrn || profileData.miniProfile?.entityUrn;
        if (!recipientUrn) throw new Error('Could not resolve recipient URN for ' + vanity);

        const recipientId = recipientUrn.split(':').pop();
        const displayName = [profileData.firstName, profileData.lastName].filter(Boolean).join(' ') || vanity;

        if (dryRun) {
          return [{
            status: 'DRY_RUN',
            recipient: displayName + ' (' + vanity + ')',
            message_preview: messageText.slice(0, 200)
          }];
        }

        // Send message via messaging API
        const res = await fetch('/voyager/api/messaging/conversations', {
          method: 'POST',
          credentials: 'include',
          headers: {
            'csrf-token': csrf,
            'x-restli-protocol-version': '2.0.0',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            recipients: [recipientUrn],
            body: messageText,
            conversationCreate: {
              eventCreate: {
                value: {
                  'com.linkedin.voyager.messaging.create.MessageCreate': {
                    body: messageText,
                    attachments: [],
                  }
                }
              },
              recipients: [recipientUrn],
              subtype: 'MEMBER_TO_MEMBER',
            }
          }),
        });

        if (!res.ok) {
          const err = await res.text();
          throw new Error('DM failed: HTTP ' + res.status + ' — ' + err.slice(0, 200));
        }

        return [{
          status: 'SENT',
          recipient: displayName + ' (' + vanity + ')',
          message_preview: messageText.slice(0, 200)
        }];
      })()
  - map:
      status: ${{ item.status }}
      recipient: ${{ item.recipient }}
      message_preview: ${{ item.message_preview }}
```

- [ ] **Step 2: Install, dry-run, commit**

```bash
./install.sh
opencli linkedin send-dm "williamhgates" --text "Hi Bill" --dry-run --format json
git add adapters/send-dm.yaml
git commit -m "feat: add linkedin send-dm adapter with dry-run"
```

---

## Task 8: `linkedin connections` + `linkedin notifications`

**Files:**
- Create: `adapters/connections.yaml`
- Create: `adapters/notifications.yaml`

- [ ] **Step 1: Write connections.yaml** (uses Voyager search API for own connections)

- [ ] **Step 2: Write notifications.yaml** (scrapes notification tab DOM)

- [ ] **Step 3: Install, test both, commit**

```bash
./install.sh
opencli linkedin connections --limit 5 --format json
opencli linkedin notifications --limit 5 --format json
git add adapters/connections.yaml adapters/notifications.yaml
git commit -m "feat: add linkedin connections + notifications adapters"
```

---

## Task 9: Smoke Test Suite

**Files:**
- Create: `tests/test-all.sh`

- [ ] **Step 1: Write test script** — runs all adapters with `--dry-run` or read-only mode, verifies JSON output parses correctly

- [ ] **Step 2: Run full suite, commit**

```bash
bash tests/test-all.sh
git add tests/
git commit -m "test: add smoke test suite for all linkedin adapters"
```

---

## Task 10: README + Final Verification

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README** with usage examples for each command

- [ ] **Step 2: Verify `opencli linkedin --help` shows all 8 commands**

```bash
opencli linkedin --help
# Expected: post, like, comment, repost, send-dm, profile, connections, notifications
# (plus built-in: search, timeline)
```

- [ ] **Step 3: Final commit**

```bash
git add README.md
git commit -m "docs: add README with full usage guide"
```
