# Some notes about HUGO and PaperMod
I migrated my blog from blogger to HUGO hosted by Cloudflare pages.  
some notes taken during the setup

## Initial Setup
I've followed the info found here https://github.com/adityatelange/hugo-PaperMod/wiki/Installation
on my macbook `brew install hugo` to perform local test  , site available on `http://localhost:1313`

to install the PaperMod theme, i followed `number4 submodule` 

## Template for posts
I've creted a file named post.md inside archetypes folder to have a template for my posts with my preferences

to create a post from the template
```
hugo new --kind post posts/new-post.md
```

## Theme Colors

To personalize the theme, modify this file 
create `assets/css/extended/theme-vars-override.css`

with the new color scheme, like mine

```
:root {
    --theme: #c5c9d0; /* Very light gray-blue background */
    --entry: #e9eaf3; /* Slightly darker for entries */
    --primary: rgba(13, 23, 98, 0.92); /* Deep blue (inverted from gold) */
    --secondary: rgba(32, 32, 98, 0.78); /* Muted blue */
    --tertiary: rgba(16, 28, 122, 0.16); /* Faint blue */
    --content: rgba(20, 20, 28, 0.92); /* Very dark text for readability */
    --hljs-bg: #f5f5f5; /* Light background for code highlight */
    --code-bg: #e3e6ee; /* Subtle blue-gray for code blocks */
    --border: #bfc4d1; /* Soft blue-gray border */
}

.dark {
    --theme: #111111; /* Very dark black background */
    --entry: #181818; /* Slightly lighter for entries */
    --primary: rgba(255, 215, 0, 0.92); /* Golden yellow for highlights */
    --secondary: rgba(255, 193, 7, 0.78); /* Warm yellow-orange */
    --tertiary: rgba(255, 215, 0, 0.16); /* Golden yellow, faint */
    --content: rgba(245, 245, 245, 0.88); /* Light text color */
    --hljs-bg: #232323; /* Code highlight background */
    --code-bg: #181818; /* Dark code block background */
    --border: #333; /* Dark border */
}
```