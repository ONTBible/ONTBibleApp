import Foundation
import ONTKit

/// L'adaptateur : la forme du fichier devient le domaine.
///
/// ## Pourquoi cette couche existe
///
/// `ONTKit` portait ses propres `Decodable`. Le domaine savait donc lire le
/// JSON du pipeline — un champ renommé dans le vault se propageait jusqu'au
/// cœur de l'app, et les types du domaine étaient contraints par un format de
/// fichier au lieu de l'être par l'ONT.
///
/// Ici, la dépendance va dans le bon sens. `ONTSchema` décrit le fichier —
/// engendré depuis `pipeline/src/schema.rs`, jamais écrit à la main. `ONTKit`
/// décrit l'ONT. Ce fichier est le seul endroit où les deux se rencontrent.
///
/// ## Ce que ça garantit
///
/// Les `switch` ci-dessous sont **exhaustifs**. Un type de nœud ou de bloc
/// ajouté au pipeline fait échouer la compilation de l'app, en nommant le
/// fichier et la ligne.
///
/// C'est ce qui manquait. Le décodeur précédent levait bien sur un type
/// inconnu — mais à l'exécution, sur le téléphone d'un lecteur, et seulement
/// s'il ouvrait le bon livre. Le compilateur, lui, ne rate rien et ne dérange
/// personne.
///
/// La même garantie protège le site depuis qu'il dépend de `ont::schema`.
///
/// ## Ce que ça ne garantit pas
///
/// Un **champ** ajouté à une structure ne casse rien : on ne le lit pas, voilà
/// tout. Seules les variantes d'énumération sont vérifiées, parce qu'un
/// `switch` doit les couvrir toutes. C'est la même limite que côté site, et
/// elle est acceptable : un champ ignoré ne fait pas disparaître de texte.

// MARK: - Le texte

extension Inline {
    init(_ dto: ONTSchema.Inline) {
        switch dto {
        case .text(let v):
            self = .text(v)
        case .term(let v, let lemma):
            self = .term(v, lemma: lemma)
        case .translit(let translit, let hebrew):
            self = .translit(translit, hebrew: hebrew)
        case .heb(let v):
            self = .hebrew(v)
        case .gloss(let children):
            self = .gloss(children.map(Inline.init))
        case .accentuation(let children):
            self = .accentuation(children.map(Inline.init))
        case .em(let children):
            self = .emphasis(children.map(Inline.init))
        case .link(let children, let href):
            self = .link(children.map(Inline.init), href: href)
        case .`break`:
            self = .lineBreak
        }
    }
}

extension Verse {
    init(_ dto: ONTSchema.Verse) {
        self.init(n: dto.n, nodes: dto.nodes.map(Inline.init))
    }
}

extension Block {
    init(_ dto: ONTSchema.Block) {
        switch dto {
        case .heading(let level, let nodes):
            self = .heading(level: level, nodes: nodes.map(Inline.init))
        case .verses(let verses):
            self = .verses(verses.map(Verse.init))
        case .para(let nodes):
            self = .paragraph(nodes.map(Inline.init))
        case .list(let ordered, let items):
            self = .list(ordered: ordered, items: items.map { $0.map(Inline.init) })
        case .quote(let nodes):
            self = .quote(nodes.map(Inline.init))
        case .table(let headers, let rows):
            self = .table(
                headers: headers.map { $0.map(Inline.init) },
                rows: rows.map { $0.map { $0.map(Inline.init) } }
            )
        case .rule:
            self = .rule
        }
    }
}

// MARK: - Les unités

extension Status {
    init(_ dto: ONTSchema.Status) {
        switch dto {
        case .locked: self = .locked
        case .brouillon: self = .brouillon
        }
    }
}

extension Chapter.Kind {
    init(_ dto: ONTSchema.ChapterKind) {
        switch dto {
        case .chapter: self = .chapter
        case .intro: self = .intro
        }
    }
}

extension Subtitle {
    init(_ dto: ONTSchema.Subtitle) {
        self.init(french: dto.french, hebrew: dto.hebrew, reference: dto.reference)
    }
}

extension Footer {
    init(_ dto: ONTSchema.Footer) {
        self.init(version: dto.version, locked: dto.locked, notes: dto.notes.map(Block.init))
    }
}

extension Chapter {
    init(_ dto: ONTSchema.Chapter) {
        self.init(
            id: dto.id,
            bookId: dto.bookId,
            kind: Kind(dto.kind),
            n: dto.n,
            title: dto.title,
            titleNodes: dto.titleNodes.map(Inline.init),
            subtitle: dto.subtitle.map(Subtitle.init),
            status: Status(dto.status),
            blocks: dto.blocks.map(Block.init),
            footer: dto.footer.map(Footer.init),
            verseCount: dto.verseCount,
            lemmas: dto.lemmas
        )
    }
}

// MARK: - L'arborescence

extension ChapterStub {
    init(_ dto: ONTSchema.Stub) {
        self.init(
            id: dto.id,
            n: dto.n,
            title: dto.title,
            status: Status(dto.status),
            verseCount: dto.verseCount,
            reference: dto.reference
        )
    }
}

extension BookOutline {
    init(_ dto: ONTSchema.BookOutline) {
        self.init(
            id: dto.id,
            slot: dto.slot,
            title: dto.title,
            french: dto.french,
            hebrew: dto.hebrew,
            groupId: dto.groupId,
            empty: dto.empty,
            intro: dto.intro.map(ChapterStub.init),
            chapters: dto.chapters.map(ChapterStub.init)
        )
    }
}

extension Book {
    init(_ dto: ONTSchema.Book) {
        self.init(
            id: dto.id,
            slot: dto.slot,
            title: dto.title,
            french: dto.french,
            hebrew: dto.hebrew,
            corpusId: dto.corpusId,
            modeId: dto.modeId,
            groupId: dto.groupId,
            chapters: dto.chapters.map(Chapter.init),
            intro: dto.intro.map(Chapter.init),
            empty: dto.empty
        )
    }
}

extension Conteneur {
    init(_ dto: ONTSchema.Group) {
        self.init(
            id: dto.id,
            title: dto.title,
            french: dto.french,
            glose: dto.glose,
            rupture: dto.rupture
        )
    }
}

extension Mode {
    init(_ dto: ONTSchema.ModeOutline) {
        self.init(
            id: dto.id,
            title: dto.title,
            french: dto.french,
            glose: dto.glose,
            order: dto.order,
            groups: dto.groups.map(Conteneur.init),
            books: dto.books.map(BookOutline.init)
        )
    }
}

extension Corpus {
    init(_ dto: ONTSchema.CorpusOutline) {
        self.init(
            id: dto.id,
            title: dto.title,
            french: dto.french,
            glose: dto.glose,
            order: dto.order,
            modes: dto.modes.map(Mode.init)
        )
    }
}

// MARK: - Le lexique

extension Occurrence.Level {
    init(_ dto: ONTSchema.TermLevel) {
        switch dto {
        case .body: self = .body
        case .gloss: self = .gloss
        }
    }
}

extension Occurrence {
    init(_ dto: ONTSchema.Occurrence) {
        self.init(
            bookId: dto.bookId,
            chapterId: dto.chapterId,
            verse: dto.verse,
            form: dto.form,
            level: Level(dto.level),
            snippet: dto.snippet
        )
    }
}

extension GlossaryEntry {
    init(_ dto: ONTSchema.GlossaryEntry) {
        self.init(
            lemma: dto.lemma,
            title: dto.title,
            tagged: dto.tagged,
            forms: dto.forms,
            hebrew: dto.hebrew,
            rendering: dto.rendering,
            definition: dto.definition.map { $0.map(Block.init) },
            taggingNote: dto.taggingNote.map { $0.map(Block.init) },
            firstUse: dto.firstUse,
            sourceSection: dto.sourceSection,
            count: dto.count,
            bodyCount: dto.bodyCount,
            glossCount: dto.glossCount
        )
    }
}

// MARK: - La recherche et le vivier

extension SearchRecord.Kind {
    init(_ dto: ONTSchema.RecordKind) {
        switch dto {
        case .verse: self = .verse
        case .heading: self = .heading
        case .prose: self = .prose
        }
    }
}

extension SearchRecord {
    init(_ dto: ONTSchema.SearchRecord) {
        self.init(
            b: dto.b, c: dto.c, v: dto.v, k: Kind(dto.k),
            t: dto.t, g: dto.g, h: dto.h, l: dto.l, x: dto.x
        )
    }
}

extension DailyVerse {
    init(_ dto: ONTSchema.DailyVerse) {
        self.init(b: dto.b, c: dto.c, n: dto.n, r: dto.r, t: dto.t)
    }
}
