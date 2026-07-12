# Free Book Uploads: HTML, TXT and PDF

Readora supports free read-only books in multiple forms.

## Supported reader formats

`books.reader_format` can be:

- `CHAPTERS` — content stored in `book_chapters`
- `TXT` — plain text stored in `books.reader_content` or a `.txt` file key
- `HTML` — sanitized/trusted HTML stored in `books.reader_content` or a `.html` file key
- `PDF` — private PDF file key rendered inline with a short-lived signed URL

## Admin API workflow

### 1. Create an upload target

```http
POST /api/admin/uploads/sign
Content-Type: application/json
Cookie: admin_session=...

{
  "kind": "reader-html",
  "filename": "sample.html",
  "contentType": "text/html"
}
```

If `STORAGE_DRIVER=local`, the response includes a key and tells you to use `/api/admin/uploads/local`.

If `STORAGE_DRIVER=r2`, the response includes a signed PUT URL.

### 2A. Local upload

```http
POST /api/admin/uploads/local
Content-Type: application/json

{
  "key": "reader-html/123-sample.html",
  "contentBase64": "PGgxPkhlbGxvPC9oMT4="
}
```

### 2B. R2/S3 upload

Upload directly to the returned signed `uploadUrl` with HTTP `PUT`.

### 3. Create the book

```http
POST /api/admin/books
Content-Type: application/json

{
  "title": "My Free HTML Book",
  "slug": "my-free-html-book",
  "author": "Author Name",
  "description": "Read online for free.",
  "access": "FREE",
  "priceCents": 0,
  "readerFormat": "HTML",
  "readerContentKey": "reader-html/123-sample.html",
  "allowFreeDownload": false
}
```

For a PDF reader:

```json
{
  "access": "FREE",
  "readerFormat": "PDF",
  "readerContentKey": "reader-pdf/123-book.pdf",
  "allowFreeDownload": false
}
```

## Important note about PDFs

A browser must receive the PDF bytes to display the PDF. Readora prevents public direct access by using private storage and short-lived signed URLs, but no website can perfectly prevent copying/screenshots/downloads of content that is visible to the reader. For stronger protection, use HTML/TXT chapters and disable download buttons.
