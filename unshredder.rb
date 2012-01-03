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
    def rank_left_neighbors(strips)
        # rank the possible left neighbors by edge similarity
        @possibleLeftNeighbors = strips.reject{ |other|
            other == self
        }.map { |strip|
            {
                "strip" => strip,
                "diff" => calc_diff(strip)
            }
        }.sort_by { |item|
            item["diff"]
        }
    end

    public
    def find_right_neighbor(strips, n = 0)
        # Find the nth-highest ranked right neighbor for this strip
        strips.find_all { |strip|
            strip.possibleLeftNeighbors[n]["strip"] == self
        }.min_by { |strip|
            strip.possibleLeftNeighbors[n]["diff"]
        }
    end
end

def get_col_diff(im, x1, x2)
    # Calculate the differences between pixels in the columns normalized by the average pixel value
    sum = 0.0
    (0...im.rows).inject(0.0) { |diff, y|
        p1, p2 = im.pixel_color(x1, y), im.pixel_color(x2, y);
        sum += 0.5*(p1.red + p1.green + p1.blue + p2.red + p2.green + p2.blue)
        diff + (p1.red - p2.red).abs + (p1.green - p2.green).abs + (p1.blue - p2.blue).abs
    } / sum
end

def detect_strip_width(im, gcdDepth = 3)
    # Sort the columns by how different they are from the one before
    col_diffs = (1...im.columns).map { |i|
        get_col_diff(im, i - 1, i)
    }
    cols_by_diff = (1...im.columns).sort_by { |col|
        -col_diffs[col - 1]
    }

    # Use GCD on the top few results to estimate the width of the column.
    # (note: this may not always work...)
    gcd = cols_by_diff[0]
    gcdDepth.times { |i|
        gcd = gcd.gcd(cols_by_diff[i + 1])
    }
    gcd
end

def generate_strips(im, stripWidth, numStrips)
    (0...numStrips).map { |i|
        ImageStrip.new(im, i*stripWidth, (i + 1)*stripWidth - 1)
    }
end

def arrange_strips(strips, rankDepth = 3)
    # Rank left neighbors
    strips.each { |strip|
        strip.rank_left_neighbors(strips)
    }

    # Find a right neighbor for every strip except the rightmost one
    unrighted = strips
    rankDepth.times { |rank|
        if unrighted.length > 1
            unrighted = unrighted.find_all { |strip|
                not strip.rightNeighbor = strip.find_right_neighbor(strips, rank)
            }
        end
    }

    # sort the strips by location
    sorted = []
    strips.each { |strip|
        unless sorted.include?(strip)
            # section of strips for which we are currently finding neighbors
            section = [strip]
            loop {
                rightNeighbor = strip.rightNeighbor
                if rightNeighbor == nil || section.include?(rightNeighbor)
                    # we have reached the right edge of the image, or we have a loop (bad, but ignore)
                    sorted += section
                    break
                elsif rightNeighbor == sorted[0]
                    # we can add this subimage at the beginning
                    sorted = section + sorted
                    break
                else
                    # keep looking for neighbors...
                    section.push(rightNeighbor)
                    strip = rightNeighbor
                end
            }
        end
    }
    sorted
end

def unshred(srcFile, destFile)
    puts "Reading #{srcFile}"
    srcImage = Magick::ImageList.new(srcFile)
    stripWidth = detect_strip_width(srcImage)
    numStrips = srcImage.columns / stripWidth

    puts "strip width = #{stripWidth}"
    puts "number of strips = #{numStrips}"

    strips = arrange_strips(generate_strips(srcImage, stripWidth, numStrips))

    destImage = Magick::Image.new(srcImage.columns, srcImage.rows)
    strips.each_with_index { |strip, i|
        (strip.left..strip.right).each_with_index { |src_x, dest_x|
            (0...srcImage.rows).each { |y|
                destImage.pixel_color(i*stripWidth + dest_x, y, srcImage.pixel_color(src_x, y))
            }
        }
    }

    puts "Writing #{destFile}"
    destImage.write(destFile)
end

if ARGV.empty?
    puts "usage: #{$PROGRAM_NAME} <input file> [<output file>]"
    exit(1)
elsif !File.exist?(ARGV[0])
    puts "#{ARGV[0]} does not exist."
    exit(1)
end

srcFile = ARGV[0]
destFile = ARGV[1] || File.basename(srcFile, ".*") + "_unshredded" + File.extname(srcFile)

unshred(srcFile, destFile)

