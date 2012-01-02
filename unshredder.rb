#!/usr/bin/env ruby

require "rational"
require "rubygems"
require "RMagick"

class ImageStrip
    attr_accessor :left, :right, :possibleLeftNeighbors, :rightNeighbor

    def initialize(image, left, right)
        @image = image
        @left = left
        @right = right
    end

    private
    def calc_diff(other)
        get_col_diff(@image, @left, other.right)
    end

    public
    def find_possible_left_neighbors(strips)
        @possibleLeftNeighbors = strips.reject{ |other|
            other == self
        }.map { |other|
            {
                "strip" => other,
                "diff" => calc_diff(other)
            }
        }.sort_by { |item|
            item["diff"]
        }
    end

    public
    def find_right_neighbor(strips, rank = 0)
        strips.find_all { |other|
            other.possibleLeftNeighbors[rank]["strip"] == self
        }.min_by { |item|
            item.possibleLeftNeighbors[rank]["diff"]
        }
    end
end

def get_col_diff(im, x1, x2)
    sum = 0
    (0...im.rows).inject(0.0) { |diff, y|
        p1, p2 = im.pixel_color(x1, y), im.pixel_color(x2, y);
        sum += p1.red + p1.green + p1.blue + p2.red + p2.green + p2.blue
        diff + (p1.red - p2.red).abs + (p1.green - p2.green).abs + (p1.blue - p2.blue).abs
    } / sum
end

def detect_strip_width(im, gcdDepth = 3)
    col_diffs = (1...im.columns).map { |i|
        get_col_diff(im, i - 1, i)
    }
    cols_by_diff = (1...im.columns).sort_by { |col|
        col_diffs[col - 1]
    }

    gcd = cols_by_diff[-1]
    gcdDepth.times { |i|
        gcd = gcd.gcd(cols_by_diff[-i - 2])
    }
    gcd
end

def generate_strips(im, stripWidth, numStrips)
    (0...numStrips).map { |i|
        ImageStrip.new(im, i*stripWidth, (i + 1)*stripWidth - 1)
    }
end

def arrange_strips(strips, rankDepth = 3)
    strips.each { |strip|
        strip.find_possible_left_neighbors(strips)
    }

    rightmost = strips
    rankDepth.times { |rank|
        if rightmost.length > 1
            rightmost = rightmost.find_all { |strip|
                not strip.rightNeighbor = strip.find_right_neighbor(strips, rank)
            }
        end
    }

    sorted = []
    strips.each { |strip|
        unless sorted.include?(strip)
            rightStrips = [strip]
            loop {
                rightNeighbor = strip.rightNeighbor
                if rightNeighbor == nil || rightStrips.include?(rightNeighbor)
                    sorted += rightStrips
                    break
                elsif sorted[0] == rightNeighbor
                    sorted = rightStrips + sorted
                    break
                else
                    rightStrips.push(rightNeighbor)
                    strip = rightNeighbor
                end
            }
        end
    }
    sorted
end

def unshred(srcFile, destFile)
    srcImage = Magick::ImageList.new(srcFile);
    stripWidth = detect_strip_width(srcImage)
    numStrips = srcImage.columns / stripWidth

    printf("strip width = %d\n", stripWidth)
    printf("number of strips = %d\n", numStrips)

    strips = arrange_strips(generate_strips(srcImage, stripWidth, numStrips))

    destImage = Magick::Image.new(srcImage.columns, srcImage.rows)
    strips.each_with_index { |strip, i|
        (strip.left..strip.right).each_with_index { |src_x, dest_x|
            (0...srcImage.rows).each { |y|
                destImage.pixel_color(i*stripWidth + dest_x, y, srcImage.pixel_color(src_x, y))
            }
        }
    }
    destImage.write(destFile)
end

if ARGV.empty?
    printf("usage: ./unshredder.rb <input file name> \n")
    exit
end

if File.exist?(ARGV[0])
    srcFile = ARGV[0]
else
    printf("%s does not exist.\n", ARGV[0])
    exit
end

destFile = ARGV[1] || File.basename(srcFile, ".*") + "_unshredded" + File.extname(srcFile)

unshred(srcFile, destFile);

