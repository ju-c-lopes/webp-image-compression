# 🖼️ WebP Image Compression

_SEO-Friendly Image Optimization for the Web_

---

This repository provides a simple and effective way to convert and compress _`jpg`_, _`jpeg`_, and _`png`_ images into **WebP format**, which is officially _recommended by Google_ for improving page performance and Core Web Vitals scores.

WebP offers significant **file size reduction** with **minimal quality loss**, helping _websites load faster_, consume _less bandwidth_, and _enhance user experience_, essential metrics for SEO.

## 🚀 Try it Instantly on Google Colab

You can **run the complete workflow** online without installing anything locally.
Click below to open the project in Google Colab:

[🔗 Run WebP Image Compression on Google Colab](https://colab.research.google.com/drive/1Cx_IyA78w_ao68Zu8rjKskQNxpifNlLj?usp=sharing)

---

### The Colab notebook includes:

Environment setup with git installation and repository cloning

Automatic WebP tool execution (`cwebp/dwebp`)

Adjustable compression quality (`default: 80`)

Automated zipping of optimized images into `webp-image-compression`

---

## ⚙️ How to Use This Package Locally

Clone the repository

```bash
git clone https://github.com/ju-c-lopes/webp-image-compression.git
cd webp-image-compression
```

### Place your images

Put all your `.jpg`, `.jpeg`, or `.png` files inside the **"images" folder**.

### Run the converter

The script below will convert all supported images into **WebP format** at `80 compress level` and place the results inside the **`/optimized` folder**:

```bash
./convert-run.sh 80
```

### Retrieve your optimized images

The converted images will be saved in the `root directory project` and automatically zipped into `optimized.zip` for easy download.

---

## 💡 Why WebP Matters for SEO

✅ **Reduced Payload Size**: Pages load faster due to smaller image files

✅ **Better Core Web Vitals**: Faster Largest Contentful Paint (LCP) and lower Total Blocking Time (TBT)

✅ **Improved User Experience**: WebP supports transparency and animation like **_`PNG/GIF`_** but is lighter

✅ **Recommended by Google**: Directly aligned with _Google PageSpeed Insights_ and _Lighthouse_ recommendations

---

## 🧠 Technical Notes

The conversion uses **_Google’s official_** `cwebp` and `dwebp` tools.

_Compression quality_ can be set between **`75–95`** (`default: 80`, a balanced choice).

For validates conversion success, ensuring that the resulting .webp files are valid and smaller than originals, you can **run the command** below:

```bash
./run-tests.sh
```

This command will run tests that validate conversion of images.

---

## 📦 Example Output

| Input Format | Output Format | Size Reduction | Quality Level              |
| ------------ | ------------- | -------------: | -------------------------- |
| JPG / PNG    | WebP          |         40–70% | Configurable (default: 80) |

---

## 📈 Author

<img src="https://i.imgur.com/65UAniY.png" alt="Juliano" title="Juliano" width="150" style="border-radius: 50%">

Developed by Juliano Lopes
<div>
<a href="https://www.linkedin.com/in/juliano-lopes-votorantim-sp/" target="_blank">
<img src="https://img.shields.io/badge/-LinkedIn-%230077B5?style=for-the-badge&logo=linkedin&logoColor=white" target="_blank">
</a><br><br><a href = "mailto:juliano.co.lopes@gmail.com">
<img src="https://img.shields.io/badge/Gmail-D14836?style=for-the-badge&logo=gmail&logoColor=white" target="_blank">
</a></div>

---

📘 License

This project is released under the MIT License.
