INSERT INTO categories(name, slug, description) VALUES
('Fiction','fiction','Premium literary and genre fiction'),
('Technology','technology','Software, AI, security and databases'),
('Business','business','Markets, startups and strategy'),
('Sci-Fi','sci-fi','Speculative futures and space stories'),
('Productivity','productivity','Focus, work and personal systems'),
('Mystery','mystery','Crime, noir and suspense')
ON CONFLICT (slug) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;

INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,epub_key,pdf_key)
SELECT 'The Red Queen Protocol','red-queen','Mira Voss',c.id,'A sharp near-future thriller about a security architect fighting an autonomous market of stolen memories.','A city of black glass woke under a red moon. Mina watched the protocol bloom across six million devices.','PAID',999,'USD',4.90,2,99,true,now()-interval '14 days','epub/red-queen.epub','pdf/red-queen.pdf' FROM categories c WHERE c.slug='technology'
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title;

INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,epub_key)
SELECT 'Silent Atlas','silent-atlas','Jon Bell',c.id,'A cartographer follows a map that redraws itself whenever someone lies.','The first country disappeared from the atlas on a rainy Tuesday.','FREE',0,'USD',4.70,2,91,true,now()-interval '25 days','epub/silent-atlas.epub' FROM categories c WHERE c.slug='fiction'
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title;

INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,epub_key)
SELECT 'Bitcoin Letters','bitcoin-letters','Nadia Stone',c.id,'Elegant essays on sovereign money, digital commerce and the ethics of peer-to-peer markets.','Money is a language before it is a tool. Bitcoin made that language portable.','PAID',650,'USD',4.80,1,87,true,now()-interval '44 days','epub/bitcoin-letters.epub' FROM categories c WHERE c.slug='business'
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title;

INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,epub_key)
SELECT 'Midnight Library of Mars','midnight-library','T. Okafor',c.id,'On Mars, an AI librarian indexes crimes before they happen.','Mars kept its dead in sealed stacks beneath the library.','PAID',825,'USD',4.90,1,95,true,now()-interval '31 days','epub/midnight-library.epub' FROM categories c WHERE c.slug='sci-fi'
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title;

INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,epub_key)
SELECT 'Deep Workflow','deep-workflow','Cal Newporter',c.id,'A practical guide to designing attention-safe systems for creators, founders and teams.','Your calendar is a moral document. It shows what you protect.','FREE',0,'USD',4.50,1,74,false,now()-interval '80 days','epub/deep-workflow.epub' FROM categories c WHERE c.slug='productivity'
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title;

INSERT INTO book_chapters(book_id, chapter_index, title, content)
SELECT b.id, 0, 'Chapter 1', 'The first country disappeared from the atlas on a rainy Tuesday. No war, no fire, no border dispute. Just blank paper where a coast had been.' FROM books b WHERE b.slug='silent-atlas'
ON CONFLICT (book_id, chapter_index) DO UPDATE SET content=EXCLUDED.content;
INSERT INTO book_chapters(book_id, chapter_index, title, content)
SELECT b.id, 1, 'Chapter 2', 'Jonas carried the atlas beneath his coat. It felt warm when people lied near it, and hot when they lied to themselves.' FROM books b WHERE b.slug='silent-atlas'
ON CONFLICT (book_id, chapter_index) DO UPDATE SET content=EXCLUDED.content;
INSERT INTO book_chapters(book_id, chapter_index, title, content)
SELECT b.id, 0, 'Attention', 'Your calendar is a moral document. It shows what you protect, what you sell and what you accidentally surrender.' FROM books b WHERE b.slug='deep-workflow'
ON CONFLICT (book_id, chapter_index) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO homepage_sections(title,slug,section_type,sort_order) VALUES
('Trending Books','trending','AUTO',10),
('New Releases','new-releases','AUTO',20),
('Recommended Books','recommended','MANUAL',30),
('Curated Collections','collections','COLLECTIONS',40)
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title, section_type=EXCLUDED.section_type, sort_order=EXCLUDED.sort_order;

INSERT INTO homepage_section_books(section_id, book_id, sort_order)
SELECT hs.id,b.id,row_number() over() FROM homepage_sections hs CROSS JOIN books b WHERE hs.slug='recommended' AND b.slug IN ('red-queen','bitcoin-letters','midnight-library','deep-workflow')
ON CONFLICT DO NOTHING;


UPDATE books SET reader_format='CHAPTERS', allow_free_download=false WHERE slug IN ('silent-atlas','deep-workflow');
-- Example of a free book uploaded as plain text stored in DB instead of chapters or file storage.
INSERT INTO books(title,slug,author,category_id,description,preview_text,access,price_cents,currency,rating,review_count,popularity_score,featured,published_at,reader_format,reader_content,allow_free_download)
SELECT 'Open Night Notes','open-night-notes','Readora Studio',c.id,'A tiny free read-only text upload example.','A small note from the Readora demo library.','FREE',0,'USD',4.20,0,55,false,now(),'TXT','A small note from the Readora demo library.

This free book demonstrates TXT/HTML/PDF reader upload support. Admins can store text directly, or upload .txt, .html and .pdf files to local storage/R2 and assign reader_content_key.',false FROM categories c WHERE c.slug='fiction'
ON CONFLICT (slug) DO UPDATE SET reader_format=EXCLUDED.reader_format, reader_content=EXCLUDED.reader_content;
