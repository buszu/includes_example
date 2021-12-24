dumas = Author.create(name: 'Alexandre Dumas')
lewis = Author.create(name: 'C.S. Lewis')
martin = Author.create(name: 'Robert C. Martin')

Book.create(author: dumas, title: 'The Three Musketeers')
Book.create(author: lewis, title: 'The Lion, the Witch and the Wardrobe')
Book.create(author: martin, title: 'Clean Code')
