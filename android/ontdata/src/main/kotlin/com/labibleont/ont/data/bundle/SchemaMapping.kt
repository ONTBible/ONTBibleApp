package com.labibleont.ont.data.bundle

import com.labibleont.ont.data.schema.Block as DtoBlock
import com.labibleont.ont.data.schema.Book as DtoBook
import com.labibleont.ont.data.schema.BookOutline as DtoBookOutline
import com.labibleont.ont.data.schema.Chapter as DtoChapter
import com.labibleont.ont.data.schema.ChapterKind as DtoChapterKind
import com.labibleont.ont.data.schema.CorpusOutline as DtoCorpusOutline
import com.labibleont.ont.data.schema.DailyVerse as DtoDailyVerse
import com.labibleont.ont.data.schema.Footer as DtoFooter
import com.labibleont.ont.data.schema.GlossaryEntry as DtoGlossaryEntry
import com.labibleont.ont.data.schema.Group as DtoGroup
import com.labibleont.ont.data.schema.Inline as DtoInline
import com.labibleont.ont.data.schema.ModeOutline as DtoModeOutline
import com.labibleont.ont.data.schema.Occurrence as DtoOccurrence
import com.labibleont.ont.data.schema.RecordKind as DtoRecordKind
import com.labibleont.ont.data.schema.SearchRecord as DtoSearchRecord
import com.labibleont.ont.data.schema.Status as DtoStatus
import com.labibleont.ont.data.schema.Stub as DtoStub
import com.labibleont.ont.data.schema.Subtitle as DtoSubtitle
import com.labibleont.ont.data.schema.TermLevel as DtoTermLevel
import com.labibleont.ont.data.schema.Verse as DtoVerse
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Conteneur
import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.ChapterKind
import com.labibleont.ont.kit.corpus.ChapterStub
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.corpus.Footer
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.Mode
import com.labibleont.ont.kit.corpus.Status
import com.labibleont.ont.kit.corpus.Subtitle
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.glossary.OccurrenceLevel
import com.labibleont.ont.kit.reader.DailyVerse
import com.labibleont.ont.kit.search.SearchKind
import com.labibleont.ont.kit.search.SearchRecord

/*
 * La traduction — DTO engendré vers domaine.
 *
 * ## Le seul endroit où les deux formes se croisent
 *
 * En amont, `schema.Inline` : la forme exacte du fichier, engendrée depuis
 * `schema.rs`, qui change quand le pipeline change. En aval, `corpus.Inline` :
 * ce qu'est un nœud de texte pour l'ONT, qui ne change que si l'ONT change.
 *
 * Un champ renommé dans le vault s'arrête donc ici. C'est ce que le chantier
 * `codegen` a défait côté iOS, où `ONTKit` portait ses propres décodeurs : le
 * domaine savait lire le JSON du pipeline, et un renommage traversait l'app
 * jusqu'au cœur.
 *
 * ## Les `when` sont exhaustifs, et c'est le filet
 *
 * Aucune branche `else` sur les unions. Un nœud ajouté à `schema.rs` fait donc
 * **échouer la compilation** ici, à l'endroit exact où il faut décider ce qu'il
 * devient. C'est l'équivalent Kotlin du `switch` exhaustif de Swift, et la
 * raison pour laquelle on ne se contente pas d'ignorer l'inconnu.
 *
 * Le rappel vaut d'être écrit : quatre types de nœuds — `heb`, `link`, `quote`,
 * `table` — ont échappé au premier relevé du site parce qu'ils ne vivent que
 * dans les définitions du lexique, jamais dans un chapitre. Un `else` les
 * aurait avalés en silence, et il aurait manqué des mots.
 *
 * ## Les noms diffèrent parfois, et c'est voulu
 *
 * `heb` devient `Hebrew`, `em` devient `Emphasis`, `break` devient `LineBreak`,
 * `para` devient `Paragraph`. Le fichier a des noms courts parce qu'il est
 * répété des dizaines de milliers de fois ; le domaine a des noms entiers parce
 * qu'on les lit. Aligner l'un sur l'autre aurait fait payer la lisibilité au
 * moins utile des deux.
 */

internal fun DtoInline.versDomaine(): Inline = when (this) {
    is DtoInline.Text -> Inline.Text(v)
    is DtoInline.Term -> Inline.Term(v, lemma)
    is DtoInline.Translit -> Inline.Translit(translit, hebrew)
    is DtoInline.Heb -> Inline.Hebrew(v)
    is DtoInline.Gloss -> Inline.Gloss(children.versDomaine())
    is DtoInline.Accentuation -> Inline.Accentuation(children.versDomaine())
    is DtoInline.Em -> Inline.Emphasis(children.versDomaine())
    is DtoInline.Link -> Inline.Link(children.versDomaine(), href)
    DtoInline.Break -> Inline.LineBreak
}

internal fun kotlin.collections.List<DtoInline>.versDomaine(): kotlin.collections.List<Inline> =
    map { it.versDomaine() }

internal fun DtoVerse.versDomaine(): Verse = Verse(n = n, nodes = nodes.versDomaine())

internal fun DtoBlock.versDomaine(): Block = when (this) {
    is DtoBlock.Heading -> Block.Heading(level = level, nodes = nodes.versDomaine())
    is DtoBlock.Verses -> Block.Verses(verses.map { it.versDomaine() })
    is DtoBlock.Para -> Block.Paragraph(nodes.versDomaine())
    is DtoBlock.List -> Block.List(ordered = ordered, items = items.map { it.versDomaine() })
    is DtoBlock.Quote -> Block.Quote(nodes.versDomaine())
    is DtoBlock.Table -> Block.Table(
        headers = headers.map { it.versDomaine() },
        rows = rows.map { ligne -> ligne.map { it.versDomaine() } },
    )
    DtoBlock.Rule -> Block.Rule
}

@JvmName("blocsVersDomaine")
internal fun kotlin.collections.List<DtoBlock>.versDomaine(): kotlin.collections.List<Block> =
    map { it.versDomaine() }

internal fun DtoStatus.versDomaine(): Status = when (this) {
    DtoStatus.LOCKED -> Status.LOCKED
    DtoStatus.BROUILLON -> Status.BROUILLON
}

internal fun DtoChapterKind.versDomaine(): ChapterKind = when (this) {
    DtoChapterKind.CHAPTER -> ChapterKind.CHAPTER
    DtoChapterKind.INTRO -> ChapterKind.INTRO
}

internal fun DtoTermLevel.versDomaine(): OccurrenceLevel = when (this) {
    DtoTermLevel.BODY -> OccurrenceLevel.BODY
    DtoTermLevel.GLOSS -> OccurrenceLevel.GLOSS
}

internal fun DtoRecordKind.versDomaine(): SearchKind = when (this) {
    DtoRecordKind.VERSE -> SearchKind.VERSE
    DtoRecordKind.HEADING -> SearchKind.HEADING
    DtoRecordKind.PROSE -> SearchKind.PROSE
}

internal fun DtoSubtitle.versDomaine(): Subtitle =
    Subtitle(french = french, hebrew = hebrew, reference = reference)

internal fun DtoFooter.versDomaine(): Footer =
    Footer(version = version, locked = locked, notes = notes.versDomaine())

internal fun DtoChapter.versDomaine(): Chapter = Chapter(
    id = id,
    bookId = bookId,
    kind = kind.versDomaine(),
    n = n,
    title = title,
    titleNodes = titleNodes.versDomaine(),
    subtitle = subtitle?.versDomaine(),
    status = status.versDomaine(),
    blocks = blocks.versDomaine(),
    footer = footer?.versDomaine(),
    verseCount = verseCount,
    lemmas = lemmas,
    // `source` ne traverse pas : c'est le chemin du fichier dans le vault, un
    // détail de production. Le domaine n'a pas à savoir d'où vient son texte.
)

internal fun DtoBook.versDomaine(): Book = Book(
    id = id,
    slot = slot,
    title = title,
    french = french,
    hebrew = hebrew,
    corpusId = corpusId,
    modeId = modeId,
    groupId = groupId,
    chapters = chapters.map { it.versDomaine() },
    intro = intro?.versDomaine(),
    empty = empty,
)

internal fun DtoStub.versDomaine(): ChapterStub = ChapterStub(
    id = id,
    n = n,
    title = title,
    status = status.versDomaine(),
    verseCount = verseCount,
    reference = reference,
)

internal fun DtoBookOutline.versDomaine(): BookOutline = BookOutline(
    id = id,
    slot = slot,
    title = title,
    french = french,
    hebrew = hebrew,
    groupId = groupId,
    empty = empty,
    intro = intro?.versDomaine(),
    chapters = chapters.map { it.versDomaine() },
)

// `Group` du DTO devient `Conteneur` du domaine — le nom engendré suit le JSON,
// le nom du domaine évite la collision avec le `Group` de Compose.
internal fun DtoGroup.versDomaine(): Conteneur = Conteneur(
    id = id,
    title = title,
    french = french,
    glose = glose,
    rupture = rupture,
)

internal fun DtoModeOutline.versDomaine(): Mode = Mode(
    id = id,
    title = title,
    french = french,
    glose = glose,
    order = order,
    groups = groups.map { it.versDomaine() },
    books = books.map { it.versDomaine() },
)

internal fun DtoCorpusOutline.versDomaine(): Corpus = Corpus(
    id = id,
    title = title,
    french = french,
    glose = glose,
    order = order,
    modes = modes.map { it.versDomaine() },
)

internal fun DtoGlossaryEntry.versDomaine(): GlossaryEntry = GlossaryEntry(
    lemma = lemma,
    title = title,
    tagged = tagged,
    forms = forms,
    hebrew = hebrew,
    rendering = rendering,
    definition = definition?.versDomaine(),
    taggingNote = taggingNote?.versDomaine(),
    firstUse = firstUse,
    sourceSection = sourceSection,
    count = count,
    bodyCount = bodyCount,
    glossCount = glossCount,
)

internal fun DtoOccurrence.versDomaine(): Occurrence = Occurrence(
    bookId = bookId,
    chapterId = chapterId,
    verse = verse,
    form = form,
    level = level.versDomaine(),
    snippet = snippet,
)

internal fun DtoSearchRecord.versDomaine(): SearchRecord = SearchRecord(
    b = b, c = c, v = v, k = k.versDomaine(), t = t, g = g, h = h, l = l, x = x,
)

internal fun DtoDailyVerse.versDomaine(): DailyVerse =
    DailyVerse(b = b, c = c, n = n, r = r, t = t)
