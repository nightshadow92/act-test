Add-Type -TypeDefinition @"
// Copyright (c) Damien Guard. All rights reserved.
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
// You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

using System;
using System.Collections.Generic;
using System.Security.Cryptography;

/// <summary>
/// Implements a 32-bit CRC hash algorithm compatible with Zip etc.
/// </summary>
/// <remarks>
/// Crc32 should only be used for backward compatibility with older file formats
/// and algorithms. It is not secure enough for new applications.
/// If you need to call multiple times for the same data either use the HashAlgorithm
/// interface or remember that the result of one Compute call needs to be ~ (XOR) before
/// being passed in as the seed for the next Compute call.
/// </remarks>
public sealed class Crc32 : HashAlgorithm
{
    public const UInt32 DefaultPolynomial = 0xedb88320u;
    public const UInt32 DefaultSeed = 0xffffffffu;

    static UInt32[] defaultTable;

    readonly UInt32 seed;
    readonly UInt32[] table;
    UInt32 hash;

    public Crc32()
        : this(DefaultPolynomial, DefaultSeed)
    {
    }

    public Crc32(UInt32 polynomial, UInt32 seed)
    {
        table = InitializeTable(polynomial);
        this.seed = hash = seed;
    }

    public override void Initialize()
    {
        hash = seed;
    }

    protected override void HashCore(byte[] array, int ibStart, int cbSize)
    {
        hash = CalculateHash(table, hash, array, ibStart, cbSize);
    }

    protected override byte[] HashFinal()
    {
        var hashBuffer = UInt32ToBigEndianBytes(~hash);
        HashValue = hashBuffer;
        return hashBuffer;
    }

    public override int HashSize { get { return 32; } }

    public static UInt32 Compute(byte[] buffer)
    {
        return Compute(DefaultSeed, buffer);
    }

    public static UInt32 Compute(UInt32 seed, byte[] buffer)
    {
        return Compute(DefaultPolynomial, seed, buffer);
    }

    public static UInt32 Compute(UInt32 polynomial, UInt32 seed, byte[] buffer)
    {
        return ~CalculateHash(InitializeTable(polynomial), seed, buffer, 0, buffer.Length);
    }

    static UInt32[] InitializeTable(UInt32 polynomial)
    {
        if (polynomial == DefaultPolynomial && defaultTable != null)
            return defaultTable;

        var createTable = new UInt32[256];
        for (var i = 0; i < 256; i++)
        {
            var entry = (UInt32)i;
            for (var j = 0; j < 8; j++)
                if ((entry & 1) == 1)
                    entry = (entry >> 1) ^ polynomial;
                else
                    entry = entry >> 1;
            createTable[i] = entry;
        }

        if (polynomial == DefaultPolynomial)
            defaultTable = createTable;

        return createTable;
    }

    static UInt32 CalculateHash(UInt32[] table, UInt32 seed, IList<byte> buffer, int start, int size)
    {
        var hash = seed;
        for (var i = start; i < start + size; i++)
            hash = (hash >> 8) ^ table[buffer[i] ^ hash & 0xff];
        return hash;
    }

    static byte[] UInt32ToBigEndianBytes(UInt32 uint32)
    {
        var result = BitConverter.GetBytes(uint32);

        if (BitConverter.IsLittleEndian)
            Array.Reverse(result);

        return result;
    }
}
"@ -PassThru | Out-Null

Function get-crc32 {
    [CmdletBinding(DefaultParameterSetName = 'PathParameterSet')]
    Param (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'PathParameterSet',
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [String[]]$Path,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'LiteralPathParameterSet',
            Position = 0,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('PSPath', 'LP')]
        [String[]]$LiteralPath
    )

    begin {
        $ErrorActionPreference = "Stop"
        $crc32 = New-Object Crc32
    }

    process {
        $paths = switch ($PSCmdlet.ParameterSetName) {
            'PathParameterSet' {
                Convert-Path -Path $Path; break
            }
            'LiteralPathParameterSet' {
                Convert-Path -LiteralPath $LiteralPath; break
            }
        }

        foreach ($path in $paths) {
            $stream = New-Object IO.FileStream($path, [System.IO.FileMode]::Open)
            $hash = [String]::Empty

            foreach ($byte in $crc32.ComputeHash($stream)) {
                $hash += $byte.toString('x2').toUpper()
            }

            $stream.Close()

            if ($PSVersionTable.PSVersion.Major -ge 6) {
                # Not in PS5
                $hashinfo = [Microsoft.PowerShell.Commands.FileHashInfo]::new()
                $hashinfo.Algorithm = 'CRC32'
                $hashinfo.Hash = $hash
                $hashinfo.Path = $path
            }
            else {
                $hashinfo = [PSCustomObject]@{
                    Algorithm = 'CRC32'
                    Hash      = $hash
                    Path      = $path
                }
            }
            $hashinfo
        }
    }
}

$ids = Get-Content .\downlist.txt
$pack = ((Invoke-RestMethod -Uri "https://gin.sadaharu.eu/Gin.txt" -Method get) -split "\n")


foreach ($item in $ids) {
    $filename = ($pack | Where-Object { $_ -match "#$($id)\s" }) -replace ".*G|.*M\] "
    write-host $filename
    $expectedhash = $filename -replace ".*([A-Z0-9]{8}).*", '$1'
    Write-Host $expectedhash
    $loop = $true
    do {
        write-host "Downloading $filename with id $id"
        if (Test-Path $filename) {
            Remove-Item $filename
        }
        node .\irc-down.js $item
        $filehash = get-crc32 -Path $filename | Select-Object -ExpandProperty hash
        Write-Host "got $filehash for $filename"
        if ($expectedhash -match $filehash) {
            $loop = $false
        }
    }
    while ($loop)
}

