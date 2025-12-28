
USE MoviesDB;
GO

-- Insert sample movie data
INSERT INTO cso.movies (title, director, release_year, genre, rating, duration_minutes, budget, box_office, description) VALUES
('The Shawshank Redemption', 'Frank Darabont', 1994, 'Drama', 9.3, 142, 25000000, 16000000, 'Two imprisoned men bond over a number of years, finding solace and eventual redemption through acts of common decency.'),
('The Godfather', 'Francis Ford Coppola', 1972, 'Crime', 9.2, 175, 6000000, 245066411, 'The aging patriarch of an organized crime dynasty transfers control of his clandestine empire to his reluctant son.'),
('The Dark Knight', 'Christopher Nolan', 2008, 'Action', 9.0, 152, 185000000, 1004558444, 'When the menace known as the Joker wreaks havoc and chaos on the people of Gotham, Batman must accept one of the greatest psychological and physical tests.'),
('Pulp Fiction', 'Quentin Tarantino', 1994, 'Crime', 8.9, 154, 8000000, 214179088, 'The lives of two mob hitmen, a boxer, a gangster and his wife intertwine in four tales of violence and redemption.'),
('Forrest Gump', 'Robert Zemeckis', 1994, 'Drama', 8.8, 142, 55000000, 677387716, 'The presidencies of Kennedy and Johnson, the events of Vietnam, Watergate and other historical events unfold from the perspective of an Alabama man.'),
('Inception', 'Christopher Nolan', 2010, 'Sci-Fi', 8.8, 148, 160000000, 836836967, 'A thief who steals corporate secrets through the use of dream-sharing technology is given the inverse task of planting an idea.'),
('The Matrix', 'The Wachowskis', 1999, 'Sci-Fi', 8.7, 136, 63000000, 467222824, 'A computer programmer is led to fight an underground war against powerful computers who have constructed his entire reality with a system called the Matrix.'),
('Goodfellas', 'Martin Scorsese', 1990, 'Crime', 8.7, 146, 25000000, 46836394, 'The story of Henry Hill and his life in the mob, covering his relationship with his wife Karen Hill and his mob partners.'),
('The Lord of the Rings: The Return of the King', 'Peter Jackson', 2003, 'Fantasy', 8.9, 201, 94000000, 1142456534, 'Gandalf and Aragorn lead the World of Men against Saurons army to draw his gaze from Frodo and Sam as they approach Mount Doom.'),
('Fight Club', 'David Fincher', 1999, 'Drama', 8.8, 139, 63000000, 100853753, 'An insomniac office worker and a devil-may-care soapmaker form an underground fight club that evolves into something much more.'),
('Star Wars: Episode IV - A New Hope', 'George Lucas', 1977, 'Sci-Fi', 8.6, 121, 11000000, 775398007, 'Luke Skywalker joins forces with a Jedi Knight, a cocky pilot, a Wookiee and two droids to save the galaxy.'),
('The Lord of the Rings: The Fellowship of the Ring', 'Peter Jackson', 2001, 'Fantasy', 8.8, 178, 93000000, 897690072, 'A meek Hobbit from the Shire and eight companions set out on a journey to destroy the powerful One Ring.'),
('Interstellar', 'Christopher Nolan', 2014, 'Sci-Fi', 8.6, 169, 165000000, 677471339, 'A team of explorers travel through a wormhole in space in an attempt to ensure humanitys survival.'),
('Parasite', 'Bong Joon-ho', 2019, 'Thriller', 8.6, 132, 11400000, 258800000, 'A poor family schemes to become employed by a wealthy family by infiltrating their household and posing as unrelated, highly qualified individuals.'),
('Spirited Away', 'Hayao Miyazaki', 2001, 'Animation', 9.3, 125, 19000000, 395802070, 'During her familys move to the suburbs, a sullen 10-year-old girl wanders into a world ruled by gods, witches, and spirits.'),
('Saving Private Ryan', 'Steven Spielberg', 1998, 'War', 8.6, 169, 70000000, 481840909, 'Following the Normandy Landings, a group of U.S. soldiers go behind enemy lines to retrieve a paratrooper whose brothers have been killed in action.'),
('The Green Mile', 'Frank Darabont', 1999, 'Fantasy', 8.6, 189, 60000000, 286801374, 'The lives of guards on Death Row are affected by one of their charges: a black man accused of child murder and rape, yet who has a mysterious gift.'),
('Life Is Beautiful', 'Roberto Benigni', 1997, 'Comedy', 8.6, 116, 20000000, 230098753, 'When an open-minded Jewish librarian and his son become victims of the Holocaust, he uses a perfect mixture of will, humor, and imagination to protect his son.'),
('Se7en', 'David Fincher', 1995, 'Crime', 8.6, 127, 33000000, 327311859, 'Two detectives, a rookie and a veteran, hunt a serial killer who uses the seven deadly sins as his motives.'),
('The Silence of the Lambs', 'Jonathan Demme', 1991, 'Thriller', 8.6, 118, 19000000, 272742922, 'A young F.B.I. cadet must receive the help of an incarcerated and manipulative cannibal killer to help catch another serial killer.'),
('Schindlers List', 'Steven Spielberg', 1993, 'Biography', 8.9, 195, 22000000, 322161405, 'In German-occupied Poland during World War II, industrialist Oskar Schindler gradually becomes concerned for his Jewish workforce.'),
('12 Angry Men', 'Sidney Lumet', 1957, 'Drama', 9.0, 96, 350000, 4360000, 'A jury holdout attempts to prevent a miscarriage of justice by forcing his colleagues to reconsider the evidence.'),
('One Flew Over the Cuckoos Nest', 'Milos Forman', 1975, 'Drama', 8.7, 133, 3000000, 163200000, 'A criminal pleads insanity and is admitted to a mental institution, where he rebels against the oppressive nurse and rallies up the scared patients.'),
('The Departed', 'Martin Scorsese', 2006, 'Crime', 8.5, 151, 90000000, 291465034, 'An undercover cop and a police informant play a cat and mouse game with each other as they attempt to find out each others identity.'),
('Casablanca', 'Michael Curtiz', 1942, 'Romance', 8.5, 102, 1039000, 1373000, 'A cynical expatriate American cafe owner struggles to decide whether or not to help his former lover and her fugitive husband escape the Nazis in French Morocco.');
GO