import Foundation

/// The whole chain as an `AsyncSequence` of ordinal-carrying entries.
///
/// # Why an `AsyncSequence` and not an `AsyncStream`
///
/// `AsyncStream` is the right tool for a *push* source — a callback or delegate
/// that produces whether or not anyone is listening. A file is a pull source: it
/// produces exactly as fast as it is read. Worse, `AsyncStream`'s default
/// buffering policy is `Int.max`, so a producer task reading the file faster
/// than the UI consumes would accumulate the entire ledger in the stream's
/// buffer — reintroducing, invisibly, the whole-history-in-memory problem that
/// streaming exists to solve.
///
/// `FileHandle.AsyncBytes.lines` is demand-driven end to end: the file is read
/// only as far as the consumer has pulled. This type is a thin sequence over it
/// that spans segments, decodes one record per line, and attaches the cumulative
/// ordinal. Memory is one line plus one file buffer, whether the ledger holds a
/// thousand records or ten million.
///
/// # The sequence travels; the iterator does not
///
/// The sequence itself is a value — a list of segments and their ordinal bases —
/// so it is implicitly `Sendable` and can be handed out of ``LedgerStore`` to be
/// consumed wherever the caller likes. The *iterator* owns an open file
/// descriptor with a lock on it, is a `final class` with mutable state, and is
/// therefore not `Sendable`. That is the correct split: the plan of what to read
/// crosses isolation boundaries freely, the open file does not.
struct LedgerRecordSequence: AsyncSequence {
    typealias Element = LedgerEntry

    let segments: [LedgerSegment]

    func makeAsyncIterator() -> Iterator {
        Iterator(segments: segments)
    }

    final class Iterator: AsyncIteratorProtocol {
        private var pending: ArraySlice<LedgerSegment>
        private var open: OpenSegment?
        private let decoder = CanonicalJSON.makeDecoder()

        /// The open segment, its held lock, and how far into it we are.
        private struct OpenSegment {
            var segment: LedgerSegment
            var file: LockedFile
            var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator
            var offset: Int
        }

        init(segments: [LedgerSegment]) {
            self.pending = segments[...]
        }

        func next() async throws -> LedgerEntry? {
            while true {
                // Checked before touching the file so a cancelled zoom stops on
                // the very next element rather than after another read.
                try Task.checkCancellation()

                guard var current = open else {
                    guard let segment = pending.popFirst() else { return nil }
                    let file = try await LockedFile.openForReading(segment.url)
                    open = OpenSegment(
                        segment: segment,
                        file: file,
                        lines: file.handle.bytes.lines.makeAsyncIterator(),
                        offset: 0
                    )
                    continue
                }

                let line: String?
                do {
                    line = try await current.lines.next()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    current.file.close()
                    open = nil
                    throw LedgerError.unreadableSegment(
                        path: current.segment.url.path,
                        underlying: String(describing: error)
                    )
                }

                guard let line else {
                    current.file.close()
                    open = nil
                    continue
                }

                guard !line.isEmpty else {
                    // Blank lines are not records. Keep the offset where it is
                    // so a stray newline cannot shift every later ordinal.
                    open = current
                    continue
                }

                let ordinal = current.segment.ordinal(offsetInSegment: current.offset)
                current.offset += 1
                open = current

                do {
                    let record = try decoder.decode(LedgerRecord.self, from: Data(line.utf8))
                    return LedgerEntry(ordinal: ordinal, segmentIndex: current.segment.index, record: record)
                } catch {
                    // A truncated ledger ends in a partial line. Reaching it and
                    // failing loudly is the whole point: silently dropping it
                    // would render a truncated history as a complete one.
                    throw LedgerError.malformedRecord(
                        ordinal: ordinal,
                        path: current.segment.url.path,
                        underlying: String(describing: error)
                    )
                }
            }
        }

        deinit {
            open?.file.close()
        }
    }
}
