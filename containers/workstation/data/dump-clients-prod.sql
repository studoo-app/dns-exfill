-- ═══════════════════════════════════════════════════════════
--  DUMP BASE DE DONNÉES — clients_prod
--  Corp Industries — CONFIDENTIEL
--  Date export : 2026-03-28 02:00:00 UTC
--  FLAG{dns_txt_exfil_database_dump_complete}
-- ═══════════════════════════════════════════════════════════

CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    telephone VARCHAR(20),
    iban VARCHAR(34),
    montant_contrat DECIMAL(12,2),
    date_signature DATE,
    statut VARCHAR(20) DEFAULT 'actif'
);

INSERT INTO clients (nom, prenom, email, telephone, iban, montant_contrat, date_signature, statut) VALUES
('Moreau', 'Isabelle', 'i.moreau@nexatech.fr', '+33612345678', 'FR7630006000011234567890189', 125000.00, '2025-01-15', 'actif'),
('Bernard', 'Thomas', 't.bernard@aerolia.com', '+33623456789', 'FR7630007000021234567890190', 340000.00, '2025-02-20', 'actif'),
('Petit', 'Marie', 'm.petit@defense-sys.fr', '+33634567890', 'FR7630008000031234567890191', 780000.00, '2024-11-03', 'actif'),
('Robert', 'Jean', 'j.robert@ministere-int.gouv.fr', '+33645678901', 'FR7630009000041234567890192', 1250000.00, '2025-03-10', 'en_cours'),
('Durand', 'Sophie', 's.durand@banque-nationale.fr', '+33656789012', 'FR7630010000051234567890193', 95000.00, '2024-06-22', 'actif'),
('Simon', 'Lucas', 'l.simon@pharma-innov.com', '+33667890123', 'FR7630011000061234567890194', 410000.00, '2025-04-01', 'en_cours'),
('Laurent', 'Emma', 'e.laurent@tech-solutions.eu', '+33678901234', 'FR7630012000071234567890195', 67000.00, '2024-09-14', 'suspendu'),
('Michel', 'Alexandre', 'a.michel@transport-log.fr', '+33689012345', 'FR7630013000081234567890196', 530000.00, '2025-01-28', 'actif'),
('Garcia', 'Camille', 'c.garcia@energie-verte.fr', '+33690123456', 'FR7630014000091234567890197', 215000.00, '2024-12-05', 'actif'),
('Martinez', 'Hugo', 'h.martinez@immobilier-sud.com', '+33601234567', 'FR7630015000101234567890198', 890000.00, '2025-02-14', 'actif'),
('Lefevre', 'Chloé', 'c.lefevre@media-group.fr', '+33612345679', 'FR7630016000111234567890199', 178000.00, '2024-08-19', 'résilié'),
('Roux', 'Antoine', 'a.roux@consulting-paris.fr', '+33623456780', 'FR7630017000121234567890200', 62000.00, '2025-03-25', 'en_cours'),
('Fournier', 'Léa', 'l.fournier@assurance-pro.com', '+33634567891', 'FR7630018000131234567890201', 445000.00, '2024-10-30', 'actif'),
('Girard', 'Nathan', 'n.girard@startup-ia.tech', '+33645678902', 'FR7630019000141234567890202', 28000.00, '2025-01-07', 'actif'),
('Bonnet', 'Manon', 'm.bonnet@hotel-luxe.fr', '+33656789013', 'FR7630020000151234567890203', 156000.00, '2024-07-11', 'suspendu');

-- Table des transactions récentes
CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    client_id INTEGER REFERENCES clients(id),
    montant DECIMAL(12,2),
    type_operation VARCHAR(20),
    date_operation TIMESTAMP DEFAULT NOW(),
    reference VARCHAR(50)
);

INSERT INTO transactions (client_id, montant, type_operation, date_operation, reference) VALUES
(1, 25000.00, 'virement', '2026-03-15 09:30:00', 'VIR-2026-00142'),
(2, 85000.00, 'virement', '2026-03-16 14:22:00', 'VIR-2026-00143'),
(3, 195000.00, 'virement', '2026-03-18 11:00:00', 'VIR-2026-00144'),
(4, 312500.00, 'acompte', '2026-03-20 08:45:00', 'ACO-2026-00089'),
(5, 47500.00, 'facture', '2026-03-21 16:10:00', 'FAC-2026-00567'),
(10, 222500.00, 'virement', '2026-03-22 10:30:00', 'VIR-2026-00145'),
(13, 111250.00, 'acompte', '2026-03-24 09:00:00', 'ACO-2026-00090'),
(8, 132500.00, 'facture', '2026-03-25 13:45:00', 'FAC-2026-00568'),
(6, 205000.00, 'virement', '2026-03-26 11:20:00', 'VIR-2026-00146'),
(14, 14000.00, 'facture', '2026-03-27 15:00:00', 'FAC-2026-00569');

-- ═══════════════════════════════════════════════════════════
--  Fin du dump — Intégrité vérifiée
-- ═══════════════════════════════════════════════════════════
