# Shared helpers for the workflow's PowerShell tools. Dot-source it:  . "$PSScriptRoot\lib\RobloxUiTools.ps1"
# Windows PowerShell 5.1 compiles this C# 5 once per session (System.Drawing, no other dependencies).

if (-not ('RobloxUi.ImageOps' -as [type])) {
	Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace RobloxUi {
	public class Bounds {
		public int X, Y, W, H, ImageW, ImageH;
		public bool Empty;
		public double Aspect { get { return H == 0 ? 0 : (double)W / H; } }
	}

	public static class ImageOps {
		// A 32bpp ARGB copy that doesn't keep the file locked and ignores the file's DPI.
		public static Bitmap Load(string path) {
			using (var fs = File.OpenRead(path))
			using (var img = Image.FromStream(fs)) {
				var bmp = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
				using (var g = Graphics.FromImage(bmp)) {
					g.CompositingMode = CompositingMode.SourceCopy;
					g.DrawImage(img, new Rectangle(0, 0, img.Width, img.Height));
				}
				return bmp;
			}
		}

		static byte[] Bytes(Bitmap bmp, out int stride) {
			var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
			var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			stride = data.Stride;
			var buf = new byte[stride * bmp.Height];
			Marshal.Copy(data.Scan0, buf, 0, buf.Length);
			bmp.UnlockBits(data);
			return buf;
		}

		static void Write(Bitmap bmp, byte[] buf) {
			var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
			var data = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
			Marshal.Copy(buf, 0, data.Scan0, buf.Length);
			bmp.UnlockBits(data);
		}

		// Bounds of pixels with alpha >= threshold inside region, grown by margin and clamped to region.
		public static Bounds AlphaBounds(Bitmap bmp, int threshold, int margin, Rectangle region) {
			int stride;
			var buf = Bytes(bmp, out stride);
			int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
			for (int y = region.Top; y < region.Bottom; y++) {
				int row = y * stride;
				for (int x = region.Left; x < region.Right; x++) {
					if (buf[row + x * 4 + 3] >= threshold) {
						if (x < minX) minX = x;
						if (x > maxX) maxX = x;
						if (y < minY) minY = y;
						if (y > maxY) maxY = y;
					}
				}
			}
			var b = new Bounds { ImageW = bmp.Width, ImageH = bmp.Height };
			if (maxX < 0) { b.Empty = true; return b; }
			minX = Math.Max(region.Left, minX - margin);
			minY = Math.Max(region.Top, minY - margin);
			maxX = Math.Min(region.Right - 1, maxX + margin);
			maxY = Math.Min(region.Bottom - 1, maxY + margin);
			b.X = minX; b.Y = minY; b.W = maxX - minX + 1; b.H = maxY - minY + 1;
			return b;
		}

		public static Bounds AlphaBounds(Bitmap bmp, int threshold, int margin) {
			return AlphaBounds(bmp, threshold, margin, new Rectangle(0, 0, bmp.Width, bmp.Height));
		}

		// True when any pixel is less than fully opaque.
		// The largest alpha in each column (vertical = true) or row of region: where it stays under the
		// alpha threshold, a sheet can be cut without touching any item (cut-sheet.ps1).
		public static int[] LineAlphaMax(Bitmap bmp, bool vertical, Rectangle region) {
			int stride;
			var buf = Bytes(bmp, out stride);
			var max = new int[vertical ? region.Width : region.Height];
			for (int y = region.Top; y < region.Bottom; y++) {
				int row = y * stride;
				for (int x = region.Left; x < region.Right; x++) {
					int a = buf[row + x * 4 + 3];
					int k = vertical ? x - region.Left : y - region.Top;
					if (a > max[k]) max[k] = a;
				}
			}
			return max;
		}

		// Transparent regions (alpha < threshold) that don't touch the image border: sockets and windows
		// that art leaves for content. Largest first; each as its bounding box and pixel count.
		public static int[][] EnclosedHoles(Bitmap bmp, int threshold, int minArea) {
			int stride;
			var buf = Bytes(bmp, out stride);
			int w = bmp.Width, h = bmp.Height;
			var label = new int[w * h];
			var queue = new int[w * h];
			Func<int, bool> open = (p) => buf[(p / w) * stride + (p % w) * 4 + 3] < threshold;
			int head = 0, tail = 0;
			for (int x = 0; x < w; x++) { foreach (int p in new[] { x, (h - 1) * w + x }) if (label[p] == 0 && open(p)) { label[p] = -1; queue[tail++] = p; } }
			for (int y = 0; y < h; y++) { foreach (int p in new[] { y * w, y * w + w - 1 }) if (label[p] == 0 && open(p)) { label[p] = -1; queue[tail++] = p; } }
			Action<int, int> flood = null;
			var holes = new System.Collections.Generic.List<int[]>();
			flood = (seed, id) => { };
			while (head < tail) {
				int p = queue[head++]; int px = p % w, py = p / w;
				if (px > 0 && label[p - 1] == 0 && open(p - 1)) { label[p - 1] = -1; queue[tail++] = p - 1; }
				if (px < w - 1 && label[p + 1] == 0 && open(p + 1)) { label[p + 1] = -1; queue[tail++] = p + 1; }
				if (py > 0 && label[p - w] == 0 && open(p - w)) { label[p - w] = -1; queue[tail++] = p - w; }
				if (py < h - 1 && label[p + w] == 0 && open(p + w)) { label[p + w] = -1; queue[tail++] = p + w; }
			}
			int next = 1;
			for (int s = 0; s < w * h; s++) {
				if (label[s] != 0 || !open(s)) continue;
				int id = next++; head = 0; tail = 0; label[s] = id; queue[tail++] = s;
				int minX = w, minY = h, maxX = -1, maxY = -1, area = 0;
				while (head < tail) {
					int p = queue[head++]; int px = p % w, py = p / w; area++;
					if (px < minX) minX = px; if (px > maxX) maxX = px; if (py < minY) minY = py; if (py > maxY) maxY = py;
					if (px > 0 && label[p - 1] == 0 && open(p - 1)) { label[p - 1] = id; queue[tail++] = p - 1; }
					if (px < w - 1 && label[p + 1] == 0 && open(p + 1)) { label[p + 1] = id; queue[tail++] = p + 1; }
					if (py > 0 && label[p - w] == 0 && open(p - w)) { label[p - w] = id; queue[tail++] = p - w; }
					if (py < h - 1 && label[p + w] == 0 && open(p + w)) { label[p + w] = id; queue[tail++] = p + w; }
				}
				if (area >= minArea) holes.Add(new[] { minX, minY, maxX - minX + 1, maxY - minY + 1, area });
			}
			holes.Sort((a, b) => b[4].CompareTo(a[4]));
			return holes.ToArray();
		}

		// For each column in [x0, x1): the first and last row with alpha >= threshold. Returns the medians
		// { top, bottom }, or { -1, -1 } when no column has any: the band a plate's body covers.
		public static int[] BodyBand(Bitmap bmp, int x0, int x1, int threshold) {
			int stride;
			var buf = Bytes(bmp, out stride);
			var tops = new System.Collections.Generic.List<int>();
			var bottoms = new System.Collections.Generic.List<int>();
			for (int x = Math.Max(0, x0); x < Math.Min(bmp.Width, x1); x++) {
				int top = -1, bottom = -1;
				for (int y = 0; y < bmp.Height; y++) { if (buf[y * stride + x * 4 + 3] >= threshold) { if (top < 0) top = y; bottom = y; } }
				if (top >= 0) { tops.Add(top); bottoms.Add(bottom); }
			}
			if (tops.Count == 0) return new[] { -1, -1 };
			tops.Sort(); bottoms.Sort();
			return new[] { tops[tops.Count / 2], bottoms[bottoms.Count / 2] };
		}

		// For an outline frame: per column in [x0, x1), the row where the top rim (alpha >= threshold) ends
		// and the row where the bottom rim starts. Medians { innerTop, innerBottom }, or { -1, -1 } when the
		// columns are solid (no gap between rims): the clear band native content sits in.
		public static int[] InnerBand(Bitmap bmp, int x0, int x1, int threshold) {
			int stride;
			var buf = Bytes(bmp, out stride);
			var tops = new System.Collections.Generic.List<int>();
			var bottoms = new System.Collections.Generic.List<int>();
			for (int x = Math.Max(0, x0); x < Math.Min(bmp.Width, x1); x++) {
				int y = 0, h = bmp.Height;
				while (y < h && buf[y * stride + x * 4 + 3] < threshold) y++;
				while (y < h && buf[y * stride + x * 4 + 3] >= threshold) y++;
				int b = h - 1;
				while (b >= 0 && buf[b * stride + x * 4 + 3] < threshold) b--;
				while (b >= 0 && buf[b * stride + x * 4 + 3] >= threshold) b--;
				if (y < b) { tops.Add(y); bottoms.Add(b); }
			}
			if (tops.Count < Math.Max(1, (x1 - x0) / 4)) return new[] { -1, -1 };
			tops.Sort(); bottoms.Sort();
			return new[] { tops[tops.Count / 2], bottoms[bottoms.Count / 2] };
		}

		public static bool HasTransparency(Bitmap bmp) {
			int stride;
			var buf = Bytes(bmp, out stride);
			for (int y = 0; y < bmp.Height; y++) {
				int row = y * stride;
				for (int x = 0; x < bmp.Width; x++) {
					if (buf[row + x * 4 + 3] < 255) return true;
				}
			}
			return false;
		}

		public static Bitmap Crop(Bitmap src, Rectangle r) {
			var dst = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
			using (var g = Graphics.FromImage(dst)) {
				g.CompositingMode = CompositingMode.SourceCopy;
				g.DrawImage(src, new Rectangle(0, 0, r.Width, r.Height), r, GraphicsUnit.Pixel);
			}
			return dst;
		}

		// Draws src (or its sub-rect) into dst at rect with high-quality filtering and alpha blending.
		public static void DrawHq(Graphics g, Bitmap src, Rectangle srcRect, RectangleF dstRect) {
			g.CompositingMode = CompositingMode.SourceOver;
			g.CompositingQuality = CompositingQuality.HighQuality;
			g.InterpolationMode = InterpolationMode.HighQualityBicubic;
			g.PixelOffsetMode = PixelOffsetMode.HighQuality;
			g.SmoothingMode = SmoothingMode.HighQuality;
			using (var attrs = new ImageAttributes()) {
				attrs.SetWrapMode(WrapMode.TileFlipXY); // no dark fringe at the edges
				g.DrawImage(src, Rectangle.Round(dstRect), srcRect.X, srcRect.Y, srcRect.Width, srcRect.Height, GraphicsUnit.Pixel, attrs);
			}
		}

		public static Bitmap ResizeHq(Bitmap src, int w, int h) {
			var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
			using (var g = Graphics.FromImage(dst)) {
				g.Clear(Color.Transparent);
				DrawHq(g, src, new Rectangle(0, 0, src.Width, src.Height), new RectangleF(0, 0, w, h));
			}
			return dst;
		}

		// Nearest-neighbour magnification: shows the exact native pixels bigger.
		public static Bitmap Magnify(Bitmap src, int factor) {
			var dst = new Bitmap(src.Width * factor, src.Height * factor, PixelFormat.Format32bppArgb);
			using (var g = Graphics.FromImage(dst)) {
				g.CompositingMode = CompositingMode.SourceCopy;
				g.InterpolationMode = InterpolationMode.NearestNeighbor;
				g.PixelOffsetMode = PixelOffsetMode.Half;
				g.DrawImage(src, new Rectangle(0, 0, dst.Width, dst.Height));
			}
			return dst;
		}

		// Sets every pixel's colour to c and keeps its alpha (white glyph masters, tinted previews).
		public static void Tint(Bitmap bmp, Color c) {
			int stride;
			var buf = Bytes(bmp, out stride);
			for (int y = 0; y < bmp.Height; y++) {
				int row = y * stride;
				for (int x = 0; x < bmp.Width; x++) {
					int i = row + x * 4;
					buf[i] = c.B; buf[i + 1] = c.G; buf[i + 2] = c.R;
				}
			}
			Write(bmp, buf);
		}

		// Turns a dark-on-transparent or dark-on-white render into a white glyph whose alpha is the
		// original coverage: alpha = srcAlpha * (1 - luminance). Used for headless-browser SVG renders.
		public static void CoverageToWhite(Bitmap bmp) {
			int stride;
			var buf = Bytes(bmp, out stride);
			for (int y = 0; y < bmp.Height; y++) {
				int row = y * stride;
				for (int x = 0; x < bmp.Width; x++) {
					int i = row + x * 4;
					double lum = (0.2126 * buf[i + 2] + 0.7152 * buf[i + 1] + 0.0722 * buf[i]) / 255.0;
					int a = (int)Math.Round(buf[i + 3] * (1.0 - lum));
					buf[i] = 255; buf[i + 1] = 255; buf[i + 2] = 255; buf[i + 3] = (byte)Math.Max(0, Math.Min(255, a));
				}
			}
			Write(bmp, buf);
		}
	}

	public static class SourceHash {
		// The workflow's one source-gate hash: LF-normalised UTF-8 bytes (BOM dropped),
		// h = (h * 31 + byte) mod 2^32, starting at 0. Matches SourceGate.luau.
		public static byte[] Normalise(byte[] raw) {
			int start = (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) ? 3 : 0;
			var ms = new MemoryStream(raw.Length);
			for (int i = start; i < raw.Length; i++) {
				if (raw[i] == 13 && i + 1 < raw.Length && raw[i + 1] == 10) continue;
				ms.WriteByte(raw[i]);
			}
			return ms.ToArray();
		}

		public static ulong Hash(byte[] bytes) {
			ulong h = 0;
			foreach (byte b in bytes) h = (h * 31 + b) % 4294967296UL;
			return h;
		}
	}
}
'@
}

function Get-RuiSha256([string]$Path) {
	(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-RuiColor([string]$Hex) {
	$h = $Hex.TrimStart('#')
	if ($h.Length -eq 6) { $h = 'FF' + $h }
	[System.Drawing.Color]::FromArgb([Convert]::ToInt32($h, 16))
}

# Flattens "a,b" strings and arrays alike: `powershell -File` passes 1,2,3 as one string, not an array.
function Split-RuiList($Value) {
	@($Value | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Expand-RuiPaths([string[]]$Path, [string[]]$Extensions = @('.png')) {
	$Path = foreach ($p in $Path) { if (Test-Path -Path $p) { $p } else { Split-RuiList $p } }
	foreach ($p in $Path) {
		if (Test-Path -LiteralPath $p -PathType Container) {
			Get-ChildItem -LiteralPath $p -File | Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
				Sort-Object Name | ForEach-Object { $_.FullName }
		} else {
			Get-ChildItem -Path $p -File -ErrorAction Stop | Sort-Object Name | ForEach-Object { $_.FullName }
		}
	}
}
