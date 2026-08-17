"""FormulaFix CLI — diagnostic and document analysis tool."""
from setuptools import setup, find_namespace_packages

setup(
    name="cli-anything-ffx",
    version="0.1.0",
    description="FormulaFix CLI: diagnostic, ADI wrapper, and markdown analysis for FormulaFix Flutter project.",
    author="Thy985",
    license="MIT",
    packages=find_namespace_packages(include=["cli_anything.*"]),
    package_data={
        "cli_anything.ffx": ["skills/*.md"],
    },
    python_requires=">=3.10",
    install_requires=[
        "click>=8.0",
    ],
    entry_points={
        "console_scripts": [
            "ffx=cli_anything.ffx.ffx_cli:cli",
        ],
    },
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
)
