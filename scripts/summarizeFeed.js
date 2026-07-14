// summarizeFeed.js - Extract feed post summaries from LinkedIn (or similar) pages
// Usage: ai-browser-control-chromeos eval "$(cat scripts/summarizeFeed.js)"
//
// Returns a JSON array of {author, time, text, reactions, comments, reposts}

(() => {
  const posts = [];
  const articles = document.querySelectorAll('article[aria-label="Feed post"], main article, li[role="listitem"]');

  articles.forEach(el => {
    const authorEl = el.querySelector('strong, [data-view-name="profile-card-badge"]');
    const timeEl = el.querySelector('time, span[dir="auto"]');
    const textEl = el.querySelector('span[dir="auto"], div[data-view-name="feed-shared-social-action-renderer"]');
    const reactionsMatch = el.innerText.match(/(\d+)\s*reactions?/);
    const commentsMatch = el.innerText.match(/(\d+)\s*comments?/);
    const repostsMatch = el.innerText.match(/(\d+)\s*(reposts?|shared this post)/i);

    if (authorEl || textEl) {
      posts.push({
        author: authorEl ? authorEl.innerText.trim() : 'Unknown',
        time: timeEl ? timeEl.innerText.trim() : '',
        text: textEl ? textEl.innerText.trim().substring(0, 300) : '',
        reactions: reactionsMatch ? reactionsMatch[1] : '',
        comments: commentsMatch ? commentsMatch[1] : '',
        reposts: repostsMatch ? repostsMatch[1] : ''
      });
    }
  });

  // Deduplicate by author+time
  const seen = new Set();
  const unique = posts.filter(p => {
    const key = `${p.author}|${p.time}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  return unique.slice(0, 20);
})();
