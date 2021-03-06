//
//  CBLQuery+FullTextSearch.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/21/13.
//
//

#import "CouchbaseLitePrivate.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLView+Internal.h"


static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd);


@implementation CBLQuery (FullTextSearch)

- (NSString*) fullTextQuery                         {return _fullTextQuery;}
- (void) setFullTextQuery:(NSString *)fullTextQuery {_fullTextQuery = [fullTextQuery copy];}
- (BOOL) fullTextSnippets                           {return _fullTextSnippets;}
- (void) setFullTextSnippets:(BOOL)fullTextSnippets {_fullTextSnippets = fullTextSnippets;}
- (BOOL) fullTextRanking                            {return _fullTextRanking;}
- (void) setFullTextRanking:(BOOL)fullTextRanking   {_fullTextRanking = fullTextRanking;}

@end




@implementation CBLFullTextQueryRow
{
    UInt64 _fullTextID;
    __weak NSString* _fullText;
    NSArray* _matchOffsets;
    NSString* _snippet;
}

@synthesize snippet=_snippet;

- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                    fullTextID: (UInt64)fullTextID
                  matchOffsets: (NSString*)matchOffsets
                         value: (id)value
{
    self = [super initWithDocID: docID sequence: sequence key: $null value: value docProperties: nil];
    if (self) {
        _fullTextID = fullTextID;
        // Parse the offsets as a space-delimited list of numbers, into an NSArray.
        // (See http://sqlite.org/fts3.html#section_4_1 )
        _matchOffsets = [[matchOffsets componentsSeparatedByString: @" "] my_map:^id(NSString* str) {
            return @([str integerValue]);
        }];
    }
    return self;
}

- (NSString*) fullText {
    if (!_fullText) {
        _fullText = [self.database _indexedTextWithID: _fullTextID];
    }
    return _fullText;
}

- (NSUInteger) matchCount {
    return _matchOffsets.count / 4;
}

- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber {
    return [_matchOffsets[4*matchNumber + 1] unsignedIntegerValue];
}

- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber {
    NSUInteger byteStart  = [_matchOffsets[4*matchNumber + 2] unsignedIntegerValue];
    NSUInteger byteLength = [_matchOffsets[4*matchNumber + 3] unsignedIntegerValue];
    NSData* rawText = [self.fullText dataUsingEncoding: NSUTF8StringEncoding];
    return NSMakeRange(utf8BytesToChars(rawText.bytes, 0, byteStart),
                       utf8BytesToChars(rawText.bytes, byteStart, byteStart + byteLength));
}


- (NSString*) snippetWithWordStart: (NSString*)wordStart
                           wordEnd: (NSString*)wordEnd
{
    if (!_snippet)
        return nil;
    NSMutableString* snippet = [_snippet mutableCopy];
    [snippet replaceOccurrencesOfString: @"\001" withString: wordStart
                                options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
    [snippet replaceOccurrencesOfString: @"\002" withString: wordEnd
                                options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
    return snippet;
}


// Override to add FTS result info
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        if (_snippet)
            dict[@"snippet"] = [self snippetWithWordStart: @"[" wordEnd: @"]"];
        if (_matchOffsets) {
            NSMutableArray* matches = [[NSMutableArray alloc] init];
            for (NSUInteger i = 0; i < _matchOffsets.count; i += 4) {
                [matches addObject: @{@"term": _matchOffsets[i+1],
                                      @"range": @[_matchOffsets[i+2], _matchOffsets[i+3]]}];
            }
            dict[@"matches"] = matches;
        }
    }
    return dict;
}


@end




// Determine the number of characters in a range of UTF-8 bytes. */
static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd) {
    if (byteStart == byteEnd)
        return 0;
    NSString* prefix = [[NSString alloc] initWithBytesNoCopy: (UInt8*)bytes + byteStart
                                                      length: byteEnd - byteStart
                                                    encoding: NSUTF8StringEncoding
                                                freeWhenDone: NO];
    return prefix.length;
}
